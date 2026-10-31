using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using MvcMusicStore.Demo;

var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
var regression = typeof(DemoOperations).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
    .Single(attribute => attribute.Key == "DemoReleaseRegression").Value == "true";
using var services = new ServiceCollection().AddOptions().AddLogging().BuildServiceProvider();
var checks = 0;

DemoOperations Middleware(bool enabled, bool isolated = true, string secret = null, RequestDelegate next = null)
{
    var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string>
    {
        ["Demo:Enabled"] = enabled.ToString(),
        ["Demo:IsolatedEnvironment"] = isolated.ToString(),
        ["Demo:Token"] = secret ?? token
    }).Build();
    return new DemoOperations(next ?? (context => context.Response.WriteAsync("catalog")),
        configuration, NullLogger<DemoOperations>.Instance);
}

DefaultHttpContext Request(string operation = "observe")
{
    var context = new DefaultHttpContext();
    context.RequestServices = services;
    context.Request.Scheme = "https";
    context.Request.Method = "GET";
    context.Request.Path = "/Store/Browse";
    context.Request.QueryString = new QueryString("?genre=Rock");
    context.Request.Headers["X-Demo-Operation"] = operation;
    context.Request.Headers["X-Demo-Token"] = token;
    context.Request.Headers["X-Demo-Run-Id"] = "test-01";
    context.Response.Body = new MemoryStream();
    return context;
}

void Check(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
    checks++;
}

void RefusesStartup(Action action)
{
    try { action(); }
    catch (InvalidOperationException) { checks++; return; }
    throw new InvalidOperationException("Unsafe enabled configuration was accepted.");
}

RefusesStartup(() => Middleware(true, isolated: false));
RefusesStartup(() => Middleware(true, secret: "short"));
RefusesStartup(() => Middleware(true, secret: new string('x', 257)));

var normal = Request();
normal.Request.Headers.Remove("X-Demo-Operation");
await Middleware(false).InvokeAsync(normal);
Check(normal.Response.StatusCode == 200 && normal.Response.Body.Length > 0, "Ordinary request changed.");

var disabled = Request();
await Middleware(false).InvokeAsync(disabled);
Check(disabled.Response.StatusCode == 404, "Disabled behavior was reachable.");

foreach (var invalid in new[] { "missing-token", "bad-token", "http", "post", "path", "genre", "operation", "run", "multi" })
{
    var request = Request();
    switch (invalid)
    {
        case "missing-token": request.Request.Headers.Remove("X-Demo-Token"); break;
        case "bad-token": request.Request.Headers["X-Demo-Token"] = "wrong"; break;
        case "http": request.Request.Scheme = "http"; break;
        case "post": request.Request.Method = "POST"; break;
        case "path": request.Request.Path = "/ShoppingCart/AddToCart"; break;
        case "genre": request.Request.QueryString = new QueryString("?genre=Rock&genre=Jazz"); break;
        case "operation": request.Request.Headers["X-Demo-Operation"] = "crash"; break;
        case "run": request.Request.Headers["X-Demo-Run-Id"] = "invalid run"; break;
        case "multi": request.Request.Headers["X-Demo-Operation"] = new[] { "observe", "scale" }; break;
    }
    await Middleware(true).InvokeAsync(request);
    Check(request.Response.StatusCode is 400 or 403, $"Accepted invalid request: {invalid}");
}

var healthy = Request();
var responseFeature = new StartingResponseFeature { Body = healthy.Response.Body };
healthy.Features.Set<IHttpResponseFeature>(responseFeature);
await Middleware(true).InvokeAsync(healthy);
await responseFeature.StartAsync();
Check(healthy.Response.StatusCode == 200, "Observe did not reach catalog.");
Check(healthy.Response.Headers["X-Demo-Version"] == "test-version", "Image version missing.");
Check(healthy.Response.Headers["X-Demo-Process"].ToString().Length == 32, "Process identity missing.");
Check(healthy.Response.Headers["Cache-Control"] == "no-store", "Synthetic response is cacheable.");

var timer = Stopwatch.StartNew();
var scaled = Request("scale");
await Middleware(true).InvokeAsync(scaled);
Check(timer.ElapsedMilliseconds >= 450 && scaled.Response.StatusCode == 200, "Scale delay missing.");

using var cancelled = new CancellationTokenSource();
var cancelledRequest = Request("scale");
cancelledRequest.RequestAborted = cancelled.Token;
cancelled.Cancel();
try
{
    await Middleware(true).InvokeAsync(cancelledRequest);
    throw new InvalidOperationException("Delay ignored cancellation.");
}
catch (OperationCanceledException) { checks++; }

var release = Request("release-check");
var releaseFeature = new StartingResponseFeature { Body = release.Response.Body };
release.Features.Set<IHttpResponseFeature>(releaseFeature);
var releaseNextCalls = 0;
await Middleware(true, next: context =>
{
    releaseNextCalls++;
    return context.Response.WriteAsync("catalog");
}).InvokeAsync(release);
await releaseFeature.StartAsync();
Check(release.Response.StatusCode == (regression ? 503 : 200), "Wrong baked release behavior.");
Check(releaseNextCalls == (regression ? 0 : 1), "Candidate regression reached the database action.");
Check(release.Response.Headers["X-Demo-Version"] == "test-version", "Release identity missing on error.");
var ordinaryCandidate = Request();
ordinaryCandidate.Request.Headers.Remove("X-Demo-Operation");
await Middleware(true).InvokeAsync(ordinaryCandidate);
Check(ordinaryCandidate.Response.StatusCode == 200, "Regression affected ordinary browsing.");

var bothEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
var finish = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
var entered = 0;
var concurrent = Middleware(true, next: async context =>
{
    if (Interlocked.Increment(ref entered) == 2) bothEntered.SetResult();
    await finish.Task;
});
var first = Request();
var second = Request();
var firstFeature = new StartingResponseFeature { Body = first.Response.Body };
var secondFeature = new StartingResponseFeature { Body = second.Response.Body };
first.Features.Set<IHttpResponseFeature>(firstFeature);
second.Features.Set<IHttpResponseFeature>(secondFeature);
var firstTask = concurrent.InvokeAsync(first);
var secondTask = concurrent.InvokeAsync(second);
await bothEntered.Task.WaitAsync(TimeSpan.FromSeconds(5));
await firstFeature.StartAsync();
await secondFeature.StartAsync();
Check(first.Response.Headers["X-Demo-Active-Requests"] == "2" &&
    second.Response.Headers["X-Demo-Active-Requests"] == "2", "Concurrent server demand not counted.");
Check(first.Response.Headers["X-Demo-Process"] == second.Response.Headers["X-Demo-Process"],
    "Process identity changed between requests.");
finish.SetResult();
await Task.WhenAll(firstTask, secondTask);
Console.WriteLine($"PASS: {checks} checks; baked regression={regression}.");

sealed class StartingResponseFeature : HttpResponseFeature
{
    private readonly Stack<(Func<object, Task> Callback, object State)> callbacks = new();
    public override void OnStarting(Func<object, Task> callback, object state) => callbacks.Push((callback, state));
    public async Task StartAsync()
    {
        while (callbacks.TryPop(out var entry)) await entry.Callback(entry.State);
    }
}
