using System.Linq;
using System.Threading.Tasks;
using MvcMusicStore.Models;
using MvcMusicStore.ViewModels;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace MvcMusicStore.Controllers
{
    public class ShoppingCartController : Controller
    {
        private readonly MusicStoreEntities storeDB;

        public ShoppingCartController(MusicStoreEntities context)
        {
            storeDB = context;
        }

        //
        // GET: /ShoppingCart/

        public ActionResult Index()
        {
            var cart = ShoppingCart.GetCart(storeDB, this.HttpContext);

            // Set up our ViewModel
            var viewModel = new ShoppingCartViewModel
            {
                CartItems = cart.GetCartItems(),
                CartTotal = cart.GetTotal()
            };

            // Return the view
            return View(viewModel);
        }

        //
        // GET: /ShoppingCart/AddToCart/5

        public async Task<ActionResult> AddToCart(int id)
        {
            // Retrieve the album from the database
            var addedAlbum = await storeDB.Albums
                .SingleAsync(album => album.AlbumId == id);

            // Add it to the shopping cart
            var cart = ShoppingCart.GetCart(storeDB, this.HttpContext);
            cart.AddToCart(addedAlbum);

            // Go back to the main store page for more shopping
            return RedirectToAction("Index");
        }

        //
        // AJAX: /ShoppingCart/RemoveFromCart/5

        [HttpPost]
        public async Task<ActionResult> RemoveFromCart(int id)
        {
            // Retrieve the current user's shopping cart
            var cart = ShoppingCart.GetCart(storeDB, this.HttpContext);

            // Get the name of the album to display confirmation
            var cartItem = await storeDB.Carts
                .Include(c => c.Album)
                .SingleAsync(item => item.RecordId == id);
            string albumName = cartItem.Album.Title;

            // Remove from cart
            int itemCount = cart.RemoveFromCart(id);

            string removed = (itemCount > 0) ? " 1 copy of " : string.Empty;

            // Display the confirmation message
            var results = new ShoppingCartRemoveViewModel
            {
                Message = removed + albumName +
                    " has been removed from your shopping cart.",
                CartTotal = cart.GetTotal(),
                CartCount = cart.GetCount(),
                ItemCount = itemCount,
                DeleteId = id
            };

            return Json(results);
        }

        // Converted from ChildAction to regular action - can be called via AJAX or as partial view
        public ActionResult CartSummary()
        {
            var cart = ShoppingCart.GetCart(storeDB, this.HttpContext);

            // Load full cart items with all related data for summary
            var cartItems = cart.GetCartItems()
                .Select(a => a.Album.Title)
                .OrderBy(x => x);

            ViewBag.CartCount = cartItems.Count();
            ViewBag.CartSummary = string.Join("\n", cartItems.Distinct());

            return PartialView("CartSummary");
        }
    }
}

