using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MvcMusicStore.Models;
using System.Linq;
using System.Threading.Tasks;

namespace MvcMusicStore.ViewComponents
{
    public class GenreMenuViewComponent : ViewComponent
    {
        private readonly MusicStoreEntities _context;

        public GenreMenuViewComponent(MusicStoreEntities context)
        {
            _context = context;
        }

        public async Task<IViewComponentResult> InvokeAsync()
        {
            var genres = await _context.Genres
                .OrderBy(g => g.Name)
                .Take(9)
                .ToListAsync();

            return View(genres);
        }
    }
}
