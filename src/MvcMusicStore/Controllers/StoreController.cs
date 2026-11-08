using MvcMusicStore.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using MvcMusicStore.Data;

namespace MvcMusicStore.Controllers
{
    public class StoreController : Controller
    {
        private readonly InMemoryDataStore storeDB;

        public StoreController(InMemoryDataStore context)
        {
            storeDB = context;
        }

        //
        // GET: /Store/

        public ActionResult Index()
        {
            var genres = storeDB.GetGenres();
            return View(genres);
        }


        //
        // GET: /Store/Browse?genre=Disco

        public ActionResult Browse(string genre)
        {
            // Retrieve Genre and its Associated Albums from the store
            var genreModel = storeDB.GetGenres().SingleOrDefault(g => g.Name == genre);

            if (genreModel == null)
            {
                return NotFound();
            }

            return View(genreModel);
        }

        public ActionResult Details(int id)
        {
            var album = storeDB.GetAlbum(id);
            
            if (album == null)
            {
                return NotFound();
            }
            
            return View(album);
        }

        // Converted from ChildAction to regular action - can be called via AJAX or as partial view
        public ActionResult GenreMenu()
        {
            var genres = storeDB.GetGenres()
                .OrderByDescending(
                    g => g.Albums.Sum(
                    a => a.OrderDetails.Sum(
                    od => od.Quantity)))
                .Take(9)
                .ToList();

            return PartialView(genres);
        }
    }
}