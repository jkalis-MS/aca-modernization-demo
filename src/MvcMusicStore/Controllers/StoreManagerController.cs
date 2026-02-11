using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.EntityFrameworkCore;

namespace MvcMusicStore.Controllers
{
    [Authorize(Roles = "Administrator")]
    public class StoreManagerController : Controller
    {
        private readonly MusicStoreEntities db;

        public StoreManagerController(MusicStoreEntities context)
        {
            db = context;
        }

        //
        // GET: /StoreManager/

        public async Task<ActionResult> Index()
        {
            var albums = db.Albums.Include(a => a.Genre).Include(a => a.Artist)
                .OrderBy(a => a.Price);
            return View(await albums.ToListAsync());
        }

        //
        // GET: /StoreManager/Details/5

        public async Task<ActionResult> Details(int id = 0)
        {
            Album album = await db.Albums.FindAsync(id);
            if (album == null)
            {
                return NotFound();
            }
            return View(album);
        }

        //
        // GET: /StoreManager/Create

        public async Task<ActionResult> Create()
        {
            ViewBag.GenreId = new SelectList(await db.Genres.ToListAsync(), "GenreId", "Name");
            ViewBag.ArtistId = new SelectList(await db.Artists.ToListAsync(), "ArtistId", "Name");
            return View();
        }

        //
        // POST: /StoreManager/Create

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<ActionResult> Create(Album album)
        {
            if (ModelState.IsValid)
            {
                db.Albums.Add(album);
                await db.SaveChangesAsync();
                return RedirectToAction("Index");
            }

            ViewBag.GenreId = new SelectList(await db.Genres.ToListAsync(), "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(await db.Artists.ToListAsync(), "ArtistId", "Name", album.ArtistId);
            return View(album);
        }

        //
        // GET: /StoreManager/Edit/5

        public async Task<ActionResult> Edit(int id = 0)
        {
            Album album = await db.Albums.FindAsync(id);
            if (album == null)
            {
                return NotFound();
            }
            ViewBag.GenreId = new SelectList(await db.Genres.ToListAsync(), "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(await db.Artists.ToListAsync(), "ArtistId", "Name", album.ArtistId);
            return View(album);
        }

        //
        // POST: /StoreManager/Edit/5

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<ActionResult> Edit(Album album)
        {
            if (ModelState.IsValid)
            {
                db.Entry(album).State = EntityState.Modified;
                await db.SaveChangesAsync();
                return RedirectToAction("Index");
            }
            ViewBag.GenreId = new SelectList(await db.Genres.ToListAsync(), "GenreId", "Name", album.GenreId);
            ViewBag.ArtistId = new SelectList(await db.Artists.ToListAsync(), "ArtistId", "Name", album.ArtistId);
            return View(album);
        }

        //
        // GET: /StoreManager/Delete/5

        public async Task<ActionResult> Delete(int id = 0)
        {
            Album album = await db.Albums.FindAsync(id);
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
        public async Task<ActionResult> DeleteConfirmed(int id)
        {
            Album album = await db.Albums.FindAsync(id);
            db.Albums.Remove(album);
            await db.SaveChangesAsync();
            return RedirectToAction("Index");
        }
    }
}