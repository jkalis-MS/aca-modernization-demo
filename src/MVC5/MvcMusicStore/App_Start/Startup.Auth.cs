using Microsoft.Identity.Web;
using Microsoft.Identity.Web.OWIN;
using Microsoft.Owin;
using Owin;

namespace MvcMusicStore
{
    public partial class Startup
    {
        // For more information on configuring authentication, please visit https://aka.ms/ms-id-web
        public void ConfigureAuth(IAppBuilder app)
        {
            OwinTokenAcquirerFactory factory = TokenAcquirerFactory.GetDefaultInstance<OwinTokenAcquirerFactory>();
            app.AddMicrosoftIdentityWebApp(factory);

            factory.Build();
        }
    }
}