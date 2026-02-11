# Azure Monitor OpenTelemetry Configuration

This application is configured to use Azure Monitor with OpenTelemetry for observability.

## Features Enabled

- **Distributed Tracing**: Track requests across services
- **Metrics Collection**: Monitor application performance
- **Dependency Tracking**: Track calls to databases, HTTP endpoints
- **Exception Tracking**: Automatic exception telemetry
- **Performance Profiling**: Identify performance bottlenecks

## Setup Instructions

### 1. Create Azure Application Insights Resource

1. Sign in to the [Azure Portal](https://portal.azure.com)
2. Create a new Application Insights resource
3. Copy the Connection String from the resource

### 2. Configure the Application

Update the `ConnectionString` in one of the following ways:

#### Option A: appsettings.json (for development)
```json
{
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=YOUR_KEY;IngestionEndpoint=https://YOUR_REGION.in.applicationinsights.azure.com/"
  }
}
```

#### Option B: Environment Variable (recommended for production)
```bash
export APPLICATIONINSIGHTS__CONNECTIONSTRING="InstrumentationKey=YOUR_KEY;..."
```

#### Option C: Azure App Service Configuration
Add an Application Setting in Azure Portal:
- Name: `ApplicationInsights__ConnectionString`
- Value: Your connection string

### 3. Verify Telemetry

After deploying and running the application:
1. Navigate to your Application Insights resource in Azure Portal
2. Check the "Live Metrics" to see real-time telemetry
3. View "Transaction search" to see individual requests
4. Explore "Performance" to analyze operation durations
5. Check "Failures" for exceptions and failed requests

## What's Being Monitored

The following telemetry is automatically collected:

- **HTTP Requests**: All incoming web requests
- **Dependencies**: 
  - SQL database calls (Entity Framework Core)
  - HTTP client calls
- **Exceptions**: Unhandled exceptions
- **Performance Counters**: CPU, memory, etc.
- **Custom Events**: Can be added via code

## Adding Custom Telemetry

To add custom telemetry in your controllers:

```csharp
using System.Diagnostics;

// In your controller action
var activity = Activity.Current;
activity?.SetTag("customProperty", "customValue");
activity?.AddEvent(new ActivityEvent("Custom event occurred"));
```

## Profiler (Advanced)

For production performance analysis, consider enabling Application Insights Profiler:
- Available in Azure App Service
- Captures detailed execution traces
- Identifies slow code paths

See [Profiler documentation](https://docs.microsoft.com/azure/azure-monitor/profiler/profiler-overview) for setup.

## Cost Considerations

- Application Insights has a free tier with 1GB ingestion/month
- Monitor data volume in Azure Portal
- Use sampling to reduce data if needed

## References

- [Azure Monitor OpenTelemetry](https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-enable?tabs=aspnetcore)
- [OpenTelemetry .NET](https://opentelemetry.io/docs/languages/net/)
