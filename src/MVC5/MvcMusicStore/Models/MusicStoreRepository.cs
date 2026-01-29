using System.Linq;

namespace MvcMusicStore.Models
{
    /// <summary>
    /// Repository that provides a DbContext-like interface for in-memory data
    /// </summary>
    public class MusicStoreRepository
    {
        private readonly InMemoryDataStore _dataStore;

        public MusicStoreRepository()
        {
            _dataStore = InMemoryDataStore.Instance;
        }

        public IQueryable<Album> Albums => _dataStore.Albums.Values.AsQueryable();
        public IQueryable<Genre> Genres => _dataStore.Genres.Values.AsQueryable();
        public IQueryable<Artist> Artists => _dataStore.Artists.Values.AsQueryable();
        public IQueryable<Cart> Carts => _dataStore.Carts.Values.AsQueryable();
        public IQueryable<Order> Orders => _dataStore.Orders.Values.AsQueryable();
        public IQueryable<OrderDetail> OrderDetails => _dataStore.OrderDetails.Values.AsQueryable();

        public void AddAlbum(Album album)
        {
            if (album.AlbumId == 0)
            {
                album.AlbumId = _dataStore.GetNextAlbumId();
            }
            _dataStore.Albums[album.AlbumId] = album;
        }

        public void AddGenre(Genre genre)
        {
            if (genre.GenreId == 0)
            {
                genre.GenreId = _dataStore.GetNextGenreId();
            }
            _dataStore.Genres[genre.GenreId] = genre;
        }

        public void AddArtist(Artist artist)
        {
            if (artist.ArtistId == 0)
            {
                artist.ArtistId = _dataStore.GetNextArtistId();
            }
            _dataStore.Artists[artist.ArtistId] = artist;
        }

        public void AddCart(Cart cart)
        {
            if (cart.RecordId == 0)
            {
                cart.RecordId = _dataStore.GetNextCartRecordId();
            }
            _dataStore.Carts[cart.RecordId] = cart;
        }

        public void AddOrder(Order order)
        {
            if (order.OrderId == 0)
            {
                order.OrderId = _dataStore.GetNextOrderId();
            }
            _dataStore.Orders[order.OrderId] = order;
        }

        public void AddOrderDetail(OrderDetail orderDetail)
        {
            if (orderDetail.OrderDetailId == 0)
            {
                orderDetail.OrderDetailId = _dataStore.GetNextOrderDetailId();
            }
            _dataStore.OrderDetails[orderDetail.OrderDetailId] = orderDetail;
        }

        public void RemoveAlbum(Album album)
        {
            Album removed;
            _dataStore.Albums.TryRemove(album.AlbumId, out removed);
        }

        public void RemoveCart(Cart cart)
        {
            Cart removed;
            _dataStore.Carts.TryRemove(cart.RecordId, out removed);
        }

        public void RemoveOrder(Order order)
        {
            Order removed;
            _dataStore.Orders.TryRemove(order.OrderId, out removed);
        }

        public Album FindAlbum(int id)
        {
            Album album;
            _dataStore.Albums.TryGetValue(id, out album);
            return album;
        }

        public Genre FindGenre(int id)
        {
            Genre genre;
            _dataStore.Genres.TryGetValue(id, out genre);
            return genre;
        }

        public Artist FindArtist(int id)
        {
            Artist artist;
            _dataStore.Artists.TryGetValue(id, out artist);
            return artist;
        }

        public Order FindOrder(int id)
        {
            Order order;
            _dataStore.Orders.TryGetValue(id, out order);
            return order;
        }

        public void SaveChanges()
        {
            // No-op for in-memory store
        }
    }
}
