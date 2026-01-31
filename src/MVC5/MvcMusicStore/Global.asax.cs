using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace MvcMusicStore
{
    public class MvcApplication : System.Web.HttpApplication
    {
        protected void Application_Start()
        {
            AreaRegistration.RegisterAllAreas();
            FilterConfig.RegisterGlobalFilters(GlobalFilters.Filters);
            RouteConfig.RegisterRoutes(RouteTable.Routes);

            System.Data.Entity.Database.SetInitializer(new MvcMusicStore.Models.SampleData());
        }
    }
}
