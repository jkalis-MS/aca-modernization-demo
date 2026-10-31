using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace MvcMusicStore.Demo
{
    public sealed class DemoOperations
    {
        private static readonly string ProcessId = Guid.NewGuid().ToString("N");
        private static readonly string StartedAt = DateTimeOffset.UtcNow.ToString("O");
        private static readonly Regex RunIdPattern = new("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$");
        private readonly RequestDelegate next;
        private readonly ILogger<DemoOperations> logger;
        private readonly bool enabled;
        private readonly bool regression;
        private readonly byte[] tokenHash;
        private readonly string version;
        private readonly string revision;
        private readonly string replica;
        private int activeRequests;

        public DemoOperations(RequestDelegate next, IConfiguration configuration, ILogger<DemoOperations> logger)
        {
            this.next = next;
            this.logger = logger;
            enabled = configuration.GetValue<bool>("Demo:Enabled");
            var metadata = typeof(DemoOperations).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
                .ToDictionary(attribute => attribute.Key, attribute => attribute.Value);
            version = metadata.GetValueOrDefault("DemoVersion") ?? "development";
            regression = string.Equals(metadata.GetValueOrDefault("DemoReleaseRegression"), "true",
                StringComparison.OrdinalIgnoreCase);
            revision = Environment.GetEnvironmentVariable("CONTAINER_APP_REVISION") ?? "local";
            replica = Environment.GetEnvironmentVariable("CONTAINER_APP_REPLICA_NAME")
                ?? Environment.GetEnvironmentVariable("HOSTNAME") ?? Environment.MachineName;

            if (enabled)
            {
                var token = configuration["Demo:Token"];
                if (!configuration.GetValue<bool>("Demo:IsolatedEnvironment") ||
                    string.IsNullOrWhiteSpace(token) || token.Length < 32 || token.Length > 256)
                {
                    throw new InvalidOperationException(
                        "Demo operations require an explicitly isolated environment and a secret token of 32 to 256 characters.");
                }
                tokenHash = SHA256.HashData(Encoding.UTF8.GetBytes(token));
            }

            logger.LogInformation(
                "Web process started: version={DemoVersion} revision={DemoRevision} replica={DemoReplica} process={DemoProcess} started={DemoStartedAt} demoEnabled={DemoEnabled}",
                version, revision, replica, ProcessId, StartedAt, enabled);
        }

        public async Task InvokeAsync(HttpContext context)
        {
            if (!context.Request.Headers.ContainsKey("X-Demo-Operation"))
            {
                await next(context);
                return;
            }

            if (!enabled)
            {
                await RejectAsync(context, StatusCodes.Status404NotFound, "Demo operations are disabled.");
                return;
            }

            var suppliedToken = context.Request.Headers["X-Demo-Token"];
            if (!context.Request.IsHttps || suppliedToken.Count != 1 ||
                suppliedToken[0].Length > 256 ||
                !CryptographicOperations.FixedTimeEquals(tokenHash,
                    SHA256.HashData(Encoding.UTF8.GetBytes(suppliedToken[0]))))
            {
                await RejectAsync(context, StatusCodes.Status403Forbidden, "Demo authorization failed.");
                return;
            }

            var operations = context.Request.Headers["X-Demo-Operation"];
            var runIds = context.Request.Headers["X-Demo-Run-Id"];
            var operation = operations.ToString();
            var runId = runIds.ToString();
            if (!HttpMethods.IsGet(context.Request.Method) ||
                !context.Request.Path.Equals(new PathString("/Store/Browse")) ||
                context.Request.Query["genre"].Count != 1 || context.Request.Query["genre"] != "Rock" ||
                operations.Count != 1 || (operation != "scale" && operation != "release-check" && operation != "observe") ||
                runIds.Count != 1 || !RunIdPattern.IsMatch(runId))
            {
                await RejectAsync(context, StatusCodes.Status400BadRequest, "Invalid synthetic catalog request.");
                return;
            }

            Interlocked.Increment(ref activeRequests);
            var stopwatch = Stopwatch.StartNew();
            var activity = Activity.Current;
            activity?.SetTag("demo.run_id", runId);
            activity?.SetTag("demo.operation", operation);
            activity?.SetTag("demo.version", version);
            activity?.SetTag("demo.revision", revision);
            activity?.SetTag("demo.replica", replica);
            activity?.SetTag("demo.process", ProcessId);

            context.Response.OnStarting(() =>
            {
                context.Response.Headers["Cache-Control"] = "no-store";
                context.Response.Headers["X-Demo-Version"] = version;
                context.Response.Headers["X-Demo-Revision"] = revision;
                context.Response.Headers["X-Demo-Replica"] = replica;
                context.Response.Headers["X-Demo-Process"] = ProcessId;
                context.Response.Headers["X-Demo-Started-At"] = StartedAt;
                context.Response.Headers["X-Demo-Request-Id"] = activity?.TraceId.ToString() ?? context.TraceIdentifier;
                context.Response.Headers["X-Demo-Active-Requests"] =
                    Volatile.Read(ref activeRequests).ToString(CultureInfo.InvariantCulture);
                return Task.CompletedTask;
            });

            try
            {
                // This delay ends before MVC opens a database connection.
                if (operation == "scale")
                {
                    await Task.Delay(500, context.RequestAborted);
                }
                if (operation == "release-check" && regression)
                {
                    context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
                    await context.Response.WriteAsJsonAsync(new
                    {
                        error = "Intentional synthetic release regression",
                        version, revision, replica, process = ProcessId, runId
                    }, context.RequestAborted);
                    return;
                }

                await next(context);
            }
            finally
            {
                var remaining = Interlocked.Decrement(ref activeRequests);
                logger.LogInformation(
                    "Demo request: run={DemoRunId} operation={DemoOperation} version={DemoVersion} revision={DemoRevision} replica={DemoReplica} process={DemoProcess} trace={DemoTraceId} status={DemoStatus} aborted={DemoAborted} durationMs={DemoDurationMs} active={DemoActiveRequests}",
                    runId, operation, version, revision, replica, ProcessId, activity?.TraceId.ToString(),
                    context.Response.StatusCode, context.RequestAborted.IsCancellationRequested,
                    stopwatch.Elapsed.TotalMilliseconds, remaining);
            }
        }

        private async Task RejectAsync(HttpContext context, int status, string message)
        {
            logger.LogWarning("Synthetic request rejected: status={DemoStatus} reason={DemoRejection}", status, message);
            context.Response.StatusCode = status;
            context.Response.Headers["Cache-Control"] = "no-store";
            await context.Response.WriteAsJsonAsync(new { error = message }, context.RequestAborted);
        }
    }
}
