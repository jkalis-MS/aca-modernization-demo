using System;
using System.Collections.Generic;
using System.Linq;
using MvcMusicStore.Models;

namespace MvcMusicStore.Data;

public sealed class InMemoryDataStore
{
    private readonly object _sync = new();
    private readonly Dictionary<int, Album> _albums = new();
    private readonly Dictionary<int, Genre> _genres = new();
    private readonly Dictionary<int, Artist> _artists = new();
    private readonly Dictionary<int, Cart> _carts = new();
    private readonly Dictionary<int, Order> _orders = new();
    private readonly List<OrderDetail> _orderDetails = new();
    private int _nextAlbumId = 1;
    private int _nextCartId = 1;
    private int _nextOrderId = 1;
    private int _nextOrderDetailId = 1;

    public void Initialize(IEnumerable<Genre> genres, IEnumerable<Artist> artists, IEnumerable<Album> albums)
    {
        lock (_sync)
        {
            if (_albums.Count != 0)
            {
                return;
            }

            foreach (var genre in genres)
            {
                _genres.Add(genre.GenreId, CopyGenre(genre));
            }
            foreach (var artist in artists)
            {
                _artists.Add(artist.ArtistId, CopyArtist(artist));
            }
            foreach (var album in albums)
            {
                ValidateAlbum(album);
                _albums.Add(album.AlbumId, CopyAlbum(album));
            }
            _nextAlbumId = _albums.Keys.DefaultIfEmpty(0).Max() + 1;
        }
    }

    public List<Album> GetAlbums()
    {
        lock (_sync)
        {
            return CreateCatalogSnapshot().Values.ToList();
        }
    }

    public Album GetAlbum(int id)
    {
        lock (_sync)
        {
            return CreateCatalogSnapshot().GetValueOrDefault(id);
        }
    }

    public List<Genre> GetGenres()
    {
        lock (_sync)
        {
            var albums = CreateCatalogSnapshot();
            return _genres.Values.Select(genre =>
            {
                var copy = CopyGenre(genre);
                copy.Albums = albums.Values.Where(a => a.GenreId == genre.GenreId).ToList();
                return copy;
            }).ToList();
        }
    }

    public List<Artist> GetArtists()
    {
        lock (_sync)
        {
            return _artists.Values.Select(CopyArtist).ToList();
        }
    }

    public int AddAlbum(Album album)
    {
        lock (_sync)
        {
            ValidateAlbum(album);
            var copy = CopyAlbum(album);
            copy.AlbumId = _nextAlbumId++;
            _albums.Add(copy.AlbumId, copy);
            return copy.AlbumId;
        }
    }

    public bool UpdateAlbum(Album album)
    {
        lock (_sync)
        {
            if (!_albums.ContainsKey(album.AlbumId))
            {
                return false;
            }
            ValidateAlbum(album);
            _albums[album.AlbumId] = CopyAlbum(album);
            return true;
        }
    }

    public bool DeleteAlbum(int id)
    {
        lock (_sync)
        {
            if (_orderDetails.Any(detail => detail.AlbumId == id))
            {
                throw new InvalidOperationException("An album with existing orders cannot be deleted.");
            }
            if (!_albums.Remove(id))
            {
                return false;
            }
            foreach (var item in _carts.Values.Where(c => c.AlbumId == id).ToList())
            {
                _carts.Remove(item.RecordId);
            }
            return true;
        }
    }

    public void AddToCart(string cartId, int albumId)
    {
        lock (_sync)
        {
            if (!_albums.ContainsKey(albumId))
            {
                throw new ArgumentException("Album does not exist.", nameof(albumId));
            }
            var item = _carts.Values.SingleOrDefault(c => c.CartId == cartId && c.AlbumId == albumId);
            if (item != null)
            {
                item.Count++;
                return;
            }
            var recordId = _nextCartId++;
            _carts.Add(recordId, new Cart
            {
                RecordId = recordId,
                CartId = cartId,
                AlbumId = albumId,
                Count = 1,
                DateCreated = DateTime.Now
            });
        }
    }

    public int RemoveFromCart(string cartId, int recordId)
    {
        lock (_sync)
        {
            if (!_carts.TryGetValue(recordId, out var item) || item.CartId != cartId)
            {
                return 0;
            }
            if (item.Count > 1)
            {
                return --item.Count;
            }
            _carts.Remove(recordId);
            return 0;
        }
    }

    public List<Cart> GetCartItems(string cartId)
    {
        lock (_sync)
        {
            var albums = CreateCatalogSnapshot();
            return _carts.Values.Where(c => c.CartId == cartId).Select(c => new Cart
            {
                RecordId = c.RecordId,
                CartId = c.CartId,
                AlbumId = c.AlbumId,
                Count = c.Count,
                DateCreated = c.DateCreated,
                Album = albums[c.AlbumId]
            }).ToList();
        }
    }

    public void EmptyCart(string cartId)
    {
        lock (_sync)
        {
            foreach (var item in _carts.Values.Where(c => c.CartId == cartId).ToList())
            {
                _carts.Remove(item.RecordId);
            }
        }
    }

    public void MigrateCart(string cartId, string userName)
    {
        lock (_sync)
        {
            if (cartId == userName)
            {
                return;
            }
            foreach (var item in _carts.Values.Where(c => c.CartId == cartId).ToList())
            {
                var existing = _carts.Values.SingleOrDefault(c => c.CartId == userName && c.AlbumId == item.AlbumId);
                if (existing == null)
                {
                    item.CartId = userName;
                }
                else
                {
                    existing.Count += item.Count;
                    _carts.Remove(item.RecordId);
                }
            }
        }
    }

    public int CreateOrder(string cartId, Order order)
    {
        lock (_sync)
        {
            var items = _carts.Values.Where(c => c.CartId == cartId).ToList();
            if (items.Count == 0)
            {
                throw new InvalidOperationException("Your shopping cart is empty.");
            }
            var copy = CopyOrder(order);
            copy.OrderId = _nextOrderId++;
            copy.Total = items.Sum(item => item.Count * _albums[item.AlbumId].Price);
            copy.OrderDetails = new List<OrderDetail>();
            foreach (var item in items)
            {
                var detail = new OrderDetail
                {
                    OrderDetailId = _nextOrderDetailId++,
                    OrderId = copy.OrderId,
                    AlbumId = item.AlbumId,
                    Quantity = item.Count,
                    UnitPrice = _albums[item.AlbumId].Price
                };
                copy.OrderDetails.Add(detail);
                _orderDetails.Add(detail);
                _carts.Remove(item.RecordId);
            }
            _orders.Add(copy.OrderId, copy);
            order.OrderId = copy.OrderId;
            order.Total = copy.Total;
            return copy.OrderId;
        }
    }

    public bool OwnsOrder(int orderId, string userName)
    {
        lock (_sync)
        {
            return _orders.TryGetValue(orderId, out var order) && order.Username == userName;
        }
    }

    private void ValidateAlbum(Album album)
    {
        if (!_genres.ContainsKey(album.GenreId) || !_artists.ContainsKey(album.ArtistId))
        {
            throw new ArgumentException("Select an existing genre and artist.", nameof(album));
        }
    }

    private Dictionary<int, Album> CreateCatalogSnapshot()
    {
        var genres = _genres.ToDictionary(pair => pair.Key, pair => CopyGenre(pair.Value));
        var artists = _artists.ToDictionary(pair => pair.Key, pair => CopyArtist(pair.Value));
        var albums = _albums.ToDictionary(pair => pair.Key, pair => CopyAlbum(pair.Value));
        foreach (var album in albums.Values)
        {
            album.Genre = genres[album.GenreId];
            album.Artist = artists[album.ArtistId];
            album.Genre.Albums.Add(album);
            album.OrderDetails = _orderDetails.Where(d => d.AlbumId == album.AlbumId).Select(d => new OrderDetail
            {
                OrderDetailId = d.OrderDetailId,
                OrderId = d.OrderId,
                AlbumId = d.AlbumId,
                Quantity = d.Quantity,
                UnitPrice = d.UnitPrice
            }).ToList();
        }
        return albums;
    }

    private static Genre CopyGenre(Genre genre) => new()
    {
        GenreId = genre.GenreId,
        Name = genre.Name,
        Description = genre.Description,
        Albums = new List<Album>()
    };

    private static Artist CopyArtist(Artist artist) => new() { ArtistId = artist.ArtistId, Name = artist.Name };

    private static Album CopyAlbum(Album album) => new()
    {
        AlbumId = album.AlbumId,
        GenreId = album.GenreId,
        ArtistId = album.ArtistId,
        Title = album.Title,
        Price = album.Price,
        AlbumArtUrl = album.AlbumArtUrl,
        OrderDetails = new List<OrderDetail>()
    };

    private static Order CopyOrder(Order order) => new()
    {
        Username = order.Username,
        OrderDate = order.OrderDate,
        FirstName = order.FirstName,
        LastName = order.LastName,
        Address = order.Address,
        City = order.City,
        State = order.State,
        PostalCode = order.PostalCode,
        Country = order.Country,
        Phone = order.Phone,
        Email = order.Email
    };
}
