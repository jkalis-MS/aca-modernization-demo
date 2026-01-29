using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using MvcMusicStore.Models;

namespace MvcMusicStore.Controllers
{
    public class HomeController : Controller
    {
        private MusicStoreEntities storeDB = new MusicStoreEntities();
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
            // For in-memory store, just return the first N albums
            // In a real scenario with EF, this would query by OrderDetails count
            var albums = storeDB.Albums.Take(count).ToList();
            
            // Initialize OrderDetails collection if null to prevent null reference errors
            foreach (var album in albums)
            {
                if (album.OrderDetails == null)
                {
                    album.OrderDetails = new List<OrderDetail>();
                }
            }
            
            return albums;
        }
    }
}