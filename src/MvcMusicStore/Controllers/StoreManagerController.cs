using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Rendering;
using MvcMusicStore.Data;

namespace MvcMusicStore.Controllers
{
    [Authorize(Roles = "Administrator")]
    public class StoreManagerController : Controller
    {
        private readonly InMemoryDataStore db;

        public StoreManagerController(InMemoryDataStore context)
        {
            db = context;
        }

        //
        // GET: /StoreManager/

        public ActionResult Index()
        {
            var albums = db.GetAlbums()
                .OrderBy(a => a.Price);
            return View(albums.ToList());
        }

        //
        // GET: /StoreManager/Details/5

        public ActionResult Details(int id = 0)
        {
            Album album = db.GetAlbum(id);
            if (album == null)
            {
                return NotFound();
            }
            return View(album);
        }

        //
        // GET: /StoreManager/Create

        public ActionResult Create()
        {
            ViewBag.GenreId = new SelectList(db.GetGenres(), "GenreId", "Name");
            ViewBag.ArtistId = new SelectList(db.GetArtists(), "ArtistId", "Name");
            return View();
        }

        //
        // POST: /StoreManager/Create

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Create(Album album)
        {
            ValidateReferences(album);
            if (ModelState.IsValid)
            {
                db.AddAlbum(album);
                return RedirectToAction("Index");
            }

            ViewBag.GenreId = new SelectList(db.GetGenres(), "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(db.GetArtists(), "ArtistId", "Name", album.ArtistId);
            return View(album);
        }

        //
        // GET: /StoreManager/Edit/5

        public ActionResult Edit(int id = 0)
        {
            Album album = db.GetAlbum(id);
            if (album == null)
            {
                return NotFound();
            }
            ViewBag.GenreId = new SelectList(db.GetGenres(), "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(db.GetArtists(), "ArtistId", "Name", album.ArtistId);
            return View(album);
        }

        //
        // POST: /StoreManager/Edit/5

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Edit(Album album)
        {
            ValidateReferences(album);
            if (ModelState.IsValid)
            {
                if (!db.UpdateAlbum(album))
                {
                    return NotFound();
                }
                return RedirectToAction("Index");
            }
            ViewBag.GenreId = new SelectList(db.GetGenres(), "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(db.GetArtists(), "ArtistId", "Name", album.ArtistId);
            return View(album);
        }

        //
        // GET: /StoreManager/Delete/5

        public ActionResult Delete(int id = 0)
        {
            Album album = db.GetAlbum(id);
            if (album == null)
            {
                return NotFound();
            }
            return View(album);
        }

        //
        // POST: /StoreManager/Delete/5

        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public ActionResult DeleteConfirmed(int id)
        {
            try
            {
                if (!db.DeleteAlbum(id))
                {
                    return NotFound();
                }
            }
            catch (InvalidOperationException ex)
            {
                ModelState.AddModelError("", ex.Message);
                return View("Delete", db.GetAlbum(id));
            }
            return RedirectToAction("Index");
        }

        private void ValidateReferences(Album album)
        {
            if (!db.GetGenres().Any(g => g.GenreId == album.GenreId))
            {
                ModelState.AddModelError(nameof(album.GenreId), "Select an existing genre.");
            }
            if (!db.GetArtists().Any(a => a.ArtistId == album.ArtistId))
            {
                ModelState.AddModelError(nameof(album.ArtistId), "Select an existing artist.");
            }
        }
    }
}