using MvcMusicStore.Models;
using System.Configuration;
using System.Threading.Tasks;

namespace MvcMusicStore
{
    public partial class Startup
    {
        public void ConfigureApp(IAppBuilder app)
        {
            System.Data.Entity.Database.SetInitializer(new MvcMusicStore.Models.SampleData());

            CreateAdminUser();
        }

        private async void CreateAdminUser()
        {
            string _username = ConfigurationManager.AppSettings["DefaultAdminUsername"];
            string _password = ConfigurationManager.AppSettings["DefaultAdminPassword"];
            string _role = "Administrator";

            var context = new ApplicationDbContext();
            // TODO ASP.NET identity should be replaced with ASP.NET Core identity. For more details see https://docs.microsoft.com/aspnet/core/migration/identity.
            var userManager = new UserManager<ApplicationUser>(new UserStore<ApplicationUser>(context));
            var roleManager = new RoleManager<IdentityRole>(new RoleStore<IdentityRole>(context));

            var role = new IdentityRole(_role);
            var result = await roleManager.RoleExistsAsync(_role);
            if (result == false)
            {
                await roleManager.CreateAsync(role);
            }

            var user = await userManager.FindByNameAsync(_username);
            if (user == null)
            {
                user = new ApplicationUser { UserName = _username };
                await userManager.CreateAsync(user, _password);
                await userManager.AddToRoleAsync(user.Id, _role);
            }
        }
    }
}