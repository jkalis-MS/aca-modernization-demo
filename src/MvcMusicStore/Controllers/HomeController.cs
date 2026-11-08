using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;
using MvcMusicStore.Data;

namespace MvcMusicStore.Controllers
{
    public class HomeController : Controller
    {
        private readonly InMemoryDataStore storeDB;

        public HomeController(InMemoryDataStore context)
        {
            storeDB = context;
        }

        //
        // GET: /Home/

        public ActionResult Index()
        {
            // Get most popular albums
            var albums = GetTopSellingAlbums(6);
            return View(albums);
        }


        private List<Album> GetTopSellingAlbums(int count)
        {
            // Group the order details by album and return
            // the albums with the highest count
            return storeDB.GetAlbums()
                .OrderByDescending(a => a.OrderDetails.Count())
                .Take(count)
                .ToList();
        }

        public IActionResult Error()
        {
            return View();
        }

        public IActionResult StatusErrorCode(int code)
        {
            return View("StatusErrorCode", code);
        }
    }
}