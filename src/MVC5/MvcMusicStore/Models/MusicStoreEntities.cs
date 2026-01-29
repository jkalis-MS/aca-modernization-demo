using System;
using System.Linq;

namespace MvcMusicStore.Models
{
    /// <summary>
    /// Maintains backward compatibility with existing code while using in-memory storage
    /// </summary>
    public class MusicStoreEntities
    {
        private readonly MusicStoreRepository _repository;

        public MusicStoreEntities()
        {
            _repository = new MusicStoreRepository();
        }

        // Properties that return DbSet-like collections
        public DbSetWrapper<Album> Albums => new DbSetWrapper<Album>(_repository, _repository.Albums);
        public DbSetWrapper<Genre> Genres => new DbSetWrapper<Genre>(_repository, _repository.Genres);
        public DbSetWrapper<Artist> Artists => new DbSetWrapper<Artist>(_repository, _repository.Artists);
        public DbSetWrapper<Cart> Carts => new DbSetWrapper<Cart>(_repository, _repository.Carts);
        public DbSetWrapper<Order> Orders => new DbSetWrapper<Order>(_repository, _repository.Orders);
        public DbSetWrapper<OrderDetail> OrderDetails => new DbSetWrapper<OrderDetail>(_repository, _repository.OrderDetails);

        public Album Find<T>(int id) where T : class
        {
            if (typeof(T) == typeof(Album))
                return _repository.FindAlbum(id);
            return null;
        }

        public void Add<T>(T entity) where T : class
        {
            if (entity is Album)
                _repository.AddAlbum(entity as Album);
            else if (entity is Genre)
                _repository.AddGenre(entity as Genre);
            else if (entity is Artist)
                _repository.AddArtist(entity as Artist);
            else if (entity is Cart)
                _repository.AddCart(entity as Cart);
            else if (entity is Order)
                _repository.AddOrder(entity as Order);
            else if (entity is OrderDetail)
                _repository.AddOrderDetail(entity as OrderDetail);
        }

        public void Remove<T>(T entity) where T : class
        {
            if (entity is Album)
                _repository.RemoveAlbum(entity as Album);
            else if (entity is Cart)
                _repository.RemoveCart(entity as Cart);
            else if (entity is Order)
                _repository.RemoveOrder(entity as Order);
        }

        // Mimic EF's Entry method - no-op for in-memory
        public EntityEntry<T> Entry<T>(T entity) where T : class
        {
            return new EntityEntry<T>();
        }

        public void SaveChanges()
        {
            _repository.SaveChanges();
        }

        public void Dispose()
        {
            // No-op for in-memory store
        }
    }

    /// <summary>
    /// Wrapper that provides DbSet-like functionality
    /// </summary>
    public class DbSetWrapper<T> : IQueryable<T> where T : class
    {
        private readonly MusicStoreRepository _repository;
        private readonly IQueryable<T> _queryable;

        public DbSetWrapper(MusicStoreRepository repository, IQueryable<T> queryable)
        {
            _repository = repository;
            _queryable = queryable;
        }

        // IQueryable implementation
        public Type ElementType => _queryable.ElementType;
        public System.Linq.Expressions.Expression Expression => _queryable.Expression;
        public IQueryProvider Provider => _queryable.Provider;

        // Support foreach and LINQ
        public System.Collections.Generic.IEnumerator<T> GetEnumerator()
        {
            return _queryable.GetEnumerator();
        }

        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator()
        {
            return GetEnumerator();
        }

        // Find method
        public T Find(params object[] keyValues)
        {
            if (keyValues.Length == 0) return null;
            int id = (int)keyValues[0];

            if (typeof(T) == typeof(Album))
                return _repository.FindAlbum(id) as T;
            else if (typeof(T) == typeof(Genre))
                return _repository.FindGenre(id) as T;
            else if (typeof(T) == typeof(Artist))
                return _repository.FindArtist(id) as T;
            else if (typeof(T) == typeof(Order))
                return _repository.FindOrder(id) as T;

            return null;
        }

        // Add method
        public void Add(T entity)
        {
            if (entity is Album)
                _repository.AddAlbum(entity as Album);
            else if (entity is Genre)
                _repository.AddGenre(entity as Genre);
            else if (entity is Artist)
                _repository.AddArtist(entity as Artist);
            else if (entity is Cart)
                _repository.AddCart(entity as Cart);
            else if (entity is Order)
                _repository.AddOrder(entity as Order);
            else if (entity is OrderDetail)
                _repository.AddOrderDetail(entity as OrderDetail);
        }

        // Remove method
        public void Remove(T entity)
        {
            if (entity is Album)
                _repository.RemoveAlbum(entity as Album);
            else if (entity is Cart)
                _repository.RemoveCart(entity as Cart);
            else if (entity is Order)
                _repository.RemoveOrder(entity as Order);
        }

        // Include method - for in-memory, this is a no-op since relationships are already loaded
        public IQueryable<T> Include(string path)
        {
            return _queryable;
        }
    }

    /// <summary>
    /// Mock EntityEntry for compatibility
    /// </summary>
    public class EntityEntry<T> where T : class
    {
        public object State { get; set; }
    }
}