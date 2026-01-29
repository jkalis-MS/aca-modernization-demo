using Microsoft.Identity.Web;
using Microsoft.Identity.Web.OWIN;
using Microsoft.Owin;
using Microsoft.Owin.Security.Cookies;
using Owin;
using System;
using System.Configuration;

namespace MvcMusicStore
{
    public partial class Startup
    {
        // For more information on configuring authentication, please visit https://aka.ms/ms-id-web
        public void ConfigureAuth(IAppBuilder app)
        {
            // Check if Azure AD is configured
            var clientId = ConfigurationManager.AppSettings["AzureAd:ClientId"];
            var tenantId = ConfigurationManager.AppSettings["AzureAd:TenantId"];
            
            if (string.IsNullOrEmpty(clientId) || clientId == "YOUR_CLIENT_ID" ||
                string.IsNullOrEmpty(tenantId) || tenantId == "YOUR_TENANT_ID")
            {
                // Azure AD not configured - use simple cookie auth for local testing
                Console.WriteLine("WARNING: Azure AD not configured. Running in local development mode without authentication.");
                
                app.UseCookieAuthentication(new CookieAuthenticationOptions
                {
                    AuthenticationType = "Cookies",
                    CookieSecure = CookieSecureOption.SameAsRequest,
                    LoginPath = new Microsoft.Owin.PathString("/Account/Login")
                });
                
                return;
            }

            // Configure cookie authentication - this MUST come before OpenID Connect
            app.UseCookieAuthentication(new CookieAuthenticationOptions
            {
                AuthenticationType = "Cookies",
                CookieSecure = CookieSecureOption.SameAsRequest
            });

            // Configure Microsoft Identity Web for Entra ID authentication
            OwinTokenAcquirerFactory factory = TokenAcquirerFactory.GetDefaultInstance<OwinTokenAcquirerFactory>();
            app.AddMicrosoftIdentityWebApp(factory);

            factory.Build();
        }
    }
}