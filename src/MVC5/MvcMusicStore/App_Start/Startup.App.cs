using System.Linq;
using Microsoft.Owin;
using MvcMusicStore.Models;
using Owin;

namespace MvcMusicStore
{
    public partial class Startup
    {
        public void ConfigureApp(IAppBuilder app)
        {
            // The InMemoryDataStore singleton will automatically initialize sample data
            // when it's first accessed, so we don't need to do anything here.
            // Just touch it to ensure it's initialized
            var store = InMemoryDataStore.Instance;
        }
    }
}