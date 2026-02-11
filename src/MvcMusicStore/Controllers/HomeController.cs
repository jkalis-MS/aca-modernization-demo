using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace MvcMusicStore.Controllers
{
    public class HomeController : Controller
    {
        private readonly MusicStoreEntities storeDB;

        public HomeController(MusicStoreEntities context)
        {
            storeDB = context;
        }

        //
        // GET: /Home/

        public async Task<ActionResult> Index()
        {
            // Get most popular albums
            var albums = await GetTopSellingAlbums(6);
            return View(albums);
        }


        private async Task<List<Album>> GetTopSellingAlbums(int count)
        {
            // Group the order details by album and return
            // the albums with the highest count
            return await storeDB.Albums
                .OrderByDescending(a => a.OrderDetails.Count())
                .Take(count)
                .ToListAsync();
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