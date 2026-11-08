using System;
using System.Linq;
using System.Threading.Tasks;
using MvcMusicStore.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using MvcMusicStore.Data;

namespace MvcMusicStore.Controllers
{
    [Authorize]
    public class CheckoutController : Controller
    {
        private readonly InMemoryDataStore storeDB;
        const string PromoCode = "FREE";

        public CheckoutController(InMemoryDataStore context)
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
        public ActionResult AddressAndPayment(Order order, string promoCode)
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

                //Process the order
                var cart = ShoppingCart.GetCart(storeDB, this.HttpContext);
                cart.CreateOrder(order);

                return RedirectToAction("Complete", new { id = order.OrderId });
            }
            catch (InvalidOperationException ex)
            {
                //Invalid - redisplay with errors
                ModelState.AddModelError("", ex.Message);
                return View(order);
            }
        }

        //
        // GET: /Checkout/Complete

        public ActionResult Complete(int id)
        {
            // Validate customer owns this order
            bool isValid = storeDB.OwnsOrder(id, User.Identity.Name);

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