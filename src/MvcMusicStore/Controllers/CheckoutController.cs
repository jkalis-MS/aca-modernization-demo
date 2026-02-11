using System;
using System.Linq;
using System.Threading.Tasks;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;

namespace MvcMusicStore.Controllers
{
    [Authorize]
    public class CheckoutController : Controller
    {
        private readonly MusicStoreEntities storeDB;
        const string PromoCode = "FREE";

        public CheckoutController(MusicStoreEntities context)
        {
            storeDB = context;
        }

        //
        // GET: /Checkout/

        public ActionResult AddressAndPayment()
        {
            return View();
        }

        //
        // POST: /Checkout/AddressAndPayment

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<ActionResult> AddressAndPayment(Order order, string promoCode)
        {
            if (!ModelState.IsValid)
            {
                return View(order);
            }

            try
            {
                if (!string.Equals(promoCode, PromoCode, StringComparison.OrdinalIgnoreCase))
                {
                    ModelState.AddModelError("PromoCode", "Invalid promo code");
                    return View(order);
                }

                order.Username = User.Identity.Name;
                order.OrderDate = DateTime.Now;

                //Add the Order
                storeDB.Orders.Add(order);

                //Process the order
                var cart = ShoppingCart.GetCart(storeDB, this.HttpContext);
                cart.CreateOrder(order);

                // Save all changes
                await storeDB.SaveChangesAsync();

                return RedirectToAction("Complete", new { id = order.OrderId });
            }
            catch
            {
                //Invalid - redisplay with errors
                return View(order);
            }
        }

        //
        // GET: /Checkout/Complete

        public async Task<ActionResult> Complete(int id)
        {
            // Validate customer owns this order
            bool isValid = await Task.Run(() => storeDB.Orders.Any(
                o => o.OrderId == id &&
                o.Username == User.Identity.Name));

            if (isValid)
            {
                return View(id);
            }
            else
            {
                return View("Error");
            }
        }
    }
}