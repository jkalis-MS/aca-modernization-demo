using Microsoft.AspNetCore.Mvc;
using MvcMusicStore.Data;
using MvcMusicStore.Models;
using System.Linq;
using System.Threading.Tasks;

namespace MvcMusicStore.ViewComponents
{
    public class GenreMenuViewComponent : ViewComponent
    {
        private readonly InMemoryDataStore _context;

        public GenreMenuViewComponent(InMemoryDataStore context)
        {
            _context = context;
        }

        public IViewComponentResult Invoke()
        {
            var genres = _context.GetGenres()
                .OrderBy(g => g.Name)
                .Take(9)
                .ToList();

            return View(genres);
        }
    }
}
