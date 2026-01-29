using MvcMusicStore.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace MvcMusicStore.Controllers
{
    public class StoreController : Controller
    {
        MusicStoreEntities storeDB = new MusicStoreEntities();
        //
        // GET: /Store/

        public ActionResult Index()
        {
            var genres = storeDB.Genres.ToList();

            return View(genres);
        }


        //
        // GET: /Store/Browse?genre=Disco

        public ActionResult Browse(string genre)
        {
            // Retrieve Genre and its Associated Albums from database
            var genreModel = storeDB.Genres.Include("Albums")
                .SingleOrDefault(g => g.Name == genre);
            
            if (genreModel == null)
            {
                return HttpNotFound();
            }

            return View(genreModel);
        }

        public ActionResult Details(int id) 
        {
            var album = storeDB.Albums.Find(id);
            
            if (album == null)
            {
                return HttpNotFound();
            }

            return View(album);
        }

        [ChildActionOnly]
        public ActionResult GenreMenu()
        {
            // For in-memory store, just return top 9 genres alphabetically
            // In a real scenario with EF, this would order by album sales
            var genres = storeDB.Genres
                .OrderBy(g => g.Name)
                .Take(9)
                .ToList();

            return PartialView(genres);
        }
    }
}