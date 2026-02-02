using MvcMusicStore.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace MvcMusicStore.Controllers
{
    public class StoreController : Controller
    {
        private readonly MusicStoreEntities storeDB;

        public StoreController(MusicStoreEntities context)
        {
            storeDB = context;
        }

        //
        // GET: /Store/

        public async Task<ActionResult> Index()
        {
            var genres = await storeDB.Genres.ToListAsync();
            return View(genres);
        }


        //
        // GET: /Store/Browse?genre=Disco

        public async Task<ActionResult> Browse(string genre)
        {
            // Retrieve Genre and its Associated Albums from database
            var genreModel = await storeDB.Genres
                .Include(g => g.Albums)
                .SingleAsync(g => g.Name == genre);

            return View(genreModel);
        }

        public async Task<ActionResult> Details(int id) 
        {
            var album = await storeDB.Albums
                .Include(a => a.Genre)
                .Include(a => a.Artist)
                .FirstOrDefaultAsync(a => a.AlbumId == id);
            
            if (album == null)
            {
                return NotFound();
            }
            
            return View(album);
        }

        // Converted from ChildAction to regular action - can be called via AJAX or as partial view
        public async Task<ActionResult> GenreMenu()
        {
            var genres = await storeDB.Genres
                .OrderByDescending(
                    g => g.Albums.Sum(
                    a => a.OrderDetails.Sum(
                    od => od.Quantity)))
                .Take(9)
                .ToListAsync();

            return PartialView(genres);
        }
    }
}