using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using MvcMusicStore.Data;

namespace MvcMusicStore.Models
{
    public partial class ShoppingCart
    {
        private readonly InMemoryDataStore _db;
        string ShoppingCartId { get; set; }

        public ShoppingCart(InMemoryDataStore db)
        {
            _db = db;
        }

        public const string CartSessionKey = "CartId";

        public static ShoppingCart GetCart(InMemoryDataStore db, HttpContext context)
        {
            var cart = new ShoppingCart(db);
            cart.ShoppingCartId = cart.GetCartId(context);
            return cart;
        }

        // Helper method to simplify shopping cart calls
        public static ShoppingCart GetCart(InMemoryDataStore db, Controller controller)
        {
            return GetCart(db, controller.HttpContext);
        }

        public void AddToCart(Album album)
        {
            _db.AddToCart(ShoppingCartId, album.AlbumId);
        }

        public int RemoveFromCart(int id)
        {
            return _db.RemoveFromCart(ShoppingCartId, id);
        }

        public void EmptyCart()
        {
            _db.EmptyCart(ShoppingCartId);
        }

        public List<Cart> GetCartItems()
        {
            return _db.GetCartItems(ShoppingCartId);
        }

        public int GetCount()
        {
            return GetCartItems().Sum(item => item.Count);
        }

        public decimal GetTotal()
        {
            return GetCartItems().Sum(item => item.Count * item.Album.Price);
        }

        public int CreateOrder(Order order)
        {
            return _db.CreateOrder(ShoppingCartId, order);
        }

        // We're using HttpContext to allow access to session.
        public string GetCartId(HttpContext context)
        {
            var cartId = context.Session.GetString(CartSessionKey);
            
            if (string.IsNullOrWhiteSpace(cartId))
            {
                if (!string.IsNullOrWhiteSpace(context.User?.Identity?.Name))
                {
                    cartId = context.User.Identity.Name;
                }
                else
                {
                    // Generate a new random GUID using System.Guid class
                    Guid tempCartId = Guid.NewGuid();
                    cartId = tempCartId.ToString();
                }

                // Send cartId back to session
                context.Session.SetString(CartSessionKey, cartId);
            }

            return cartId;
        }

        // When a user has logged in, migrate their shopping cart to
        // be associated with their username
        public void MigrateCart(string userName)
        {
            _db.MigrateCart(ShoppingCartId, userName);
            ShoppingCartId = userName;
        }
    }
}