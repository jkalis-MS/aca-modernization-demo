using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using MvcMusicStore.Models;

namespace MvcMusicStore.Data;

public static class DbSeeder
{
    public static async Task RecreateAndSeedAsync(MusicStoreEntities context, ILogger logger, string webRootPath = null)
    {
        try
        {
            logger.LogInformation("Dropping and recreating database...");
            
            // Delete the database
            await context.Database.EnsureDeletedAsync();
            logger.LogInformation("Database deleted successfully.");
            
            // Apply all migrations to recreate schema
            await context.Database.MigrateAsync();
            logger.LogInformation("Database recreated with migrations.");
            
            logger.LogInformation("Seeding database with sample data...");
            await SeedDataAsync(context, webRootPath);
            
            logger.LogInformation("Database recreated and seeded successfully with 100 albums!");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "An error occurred while recreating and seeding the database.");
            throw;
        }
    }

    public static async Task SeedAsync(MusicStoreEntities context, string webRootPath = null)
    {
        // Check if database already has data
        if (await context.Albums.AnyAsync())
        {
            // Database has been seeded, but ensure album art files exist
            if (!string.IsNullOrEmpty(webRootPath))
            {
                await EnsureAlbumArtAsync(context, webRootPath);
            }
            return;
        }

        await SeedDataAsync(context, webRootPath);
    }

    /// <summary>
    /// Ensures album art PNG files exist on disk and updates any stale/placeholder URLs.
    /// </summary>
    private static async Task EnsureAlbumArtAsync(MusicStoreEntities context, string webRootPath)
    {
        var albums = await context.Albums.Include(a => a.Genre).ToListAsync();
        var genreCounter = new Dictionary<int, int>();
        bool changed = false;

        foreach (var album in albums)
        {
            if (!genreCounter.TryGetValue(album.GenreId, out var count))
                count = 0;
            genreCounter[album.GenreId] = count + 1;

            var fileName = $"album-{album.AlbumId}.png";
            var expectedUrl = $"/Images/AlbumArt/{fileName}";
            var filePath = Path.Combine(webRootPath, "Images", "AlbumArt", fileName);

            // Regenerate if the file doesn't exist on disk or the URL still points to a placeholder
            if (!File.Exists(filePath) || album.AlbumArtUrl != expectedUrl)
            {
                var genreName = album.Genre?.Name ?? "Rock";
                AlbumArtGenerator.GenerateAlbumArt(filePath, genreName, count);

                album.AlbumArtUrl = expectedUrl;
                changed = true;
            }
        }

        if (changed)
        {
            await context.SaveChangesAsync();
        }
    }

    private static async Task SeedDataAsync(MusicStoreEntities context, string webRootPath)
    {
        var genres = new List<Genre>
        {
            new() { Name = "Rock" },
            new() { Name = "Jazz" },
            new() { Name = "Metal" },
            new() { Name = "Alternative" },
            new() { Name = "Disco" },
            new() { Name = "Blues" },
            new() { Name = "Latin" },
            new() { Name = "Reggae" },
            new() { Name = "Pop" },
            new() { Name = "Classical" }
        };

        await context.Genres.AddRangeAsync(genres);
        await context.SaveChangesAsync();

        // Create fictitious artists
        var artists = new List<Artist>
        {
            new() { Name = "The Velvet Thunder" },
            new() { Name = "Crimson Echo" },
            new() { Name = "Silver Horizon" },
            new() { Name = "Midnight Rebels" },
            new() { Name = "Crystal Wave" },
            new() { Name = "Sonic Dreamers" },
            new() { Name = "Electric Pulse" },
            new() { Name = "Aurora Sky" },
            new() { Name = "Neon Knights" },
            new() { Name = "The Phoenix Rising" },
            new() { Name = "Blue Note Collective" },
            new() { Name = "Smooth Velvet Trio" },
            new() { Name = "The Jazz Cats" },
            new() { Name = "Midnight Saxophone" },
            new() { Name = "Urban Grove" },
            new() { Name = "Steel Hammer" },
            new() { Name = "Iron Fist Battalion" },
            new() { Name = "Thunder Gods" },
            new() { Name = "Chaos Legion" },
            new() { Name = "Death's Whisper" },
            new() { Name = "Indie Hearts" },
            new() { Name = "The Alternative View" },
            new() { Name = "Broken Compass" },
            new() { Name = "Canvas Dreams" },
            new() { Name = "Echo Chamber" },
            new() { Name = "Disco Inferno" },
            new() { Name = "Glitter Ball" },
            new() { Name = "Funky Groove Machine" },
            new() { Name = "Saturday Night Fever" },
            new() { Name = "Studio 54 Revival" },
            new() { Name = "Delta Blues Band" },
            new() { Name = "Memphis Soul" },
            new() { Name = "Chicago Blues Brothers" },
            new() { Name = "Muddy Waters Revival" },
            new() { Name = "Crossroads Trio" },
            new() { Name = "Salsa Caliente" },
            new() { Name = "Tropical Rhythms" },
            new() { Name = "Latin Soul Collective" },
            new() { Name = "Mambo Kings" },
            new() { Name = "Bossa Nova Dreams" },
            new() { Name = "Kingston Vibes" },
            new() { Name = "Roots & Culture" },
            new() { Name = "Island Breeze" },
            new() { Name = "Rastaman Collective" },
            new() { Name = "Marley's Children" },
            new() { Name = "Pop Sensation" },
            new() { Name = "Chart Toppers" },
            new() { Name = "Catchy Melodies" },
            new() { Name = "Radio Stars" },
            new() { Name = "Mainstream Magic" },
            new() { Name = "Symphony Orchestra" },
            new() { Name = "Chamber Ensemble" },
            new() { Name = "Baroque Masters" },
            new() { Name = "Classical Virtuosos" },
            new() { Name = "The String Quartet" }
        };

        await context.Artists.AddRangeAsync(artists);
        await context.SaveChangesAsync();

        // Get genres with their IDs
        var genreRock = await context.Genres.FirstAsync(g => g.Name == "Rock");
        var genreJazz = await context.Genres.FirstAsync(g => g.Name == "Jazz");
        var genreMetal = await context.Genres.FirstAsync(g => g.Name == "Metal");
        var genreAlternative = await context.Genres.FirstAsync(g => g.Name == "Alternative");
        var genreDisco = await context.Genres.FirstAsync(g => g.Name == "Disco");
        var genreBlues = await context.Genres.FirstAsync(g => g.Name == "Blues");
        var genreLatin = await context.Genres.FirstAsync(g => g.Name == "Latin");
        var genreReggae = await context.Genres.FirstAsync(g => g.Name == "Reggae");
        var genrePop = await context.Genres.FirstAsync(g => g.Name == "Pop");
        var genreClassical = await context.Genres.FirstAsync(g => g.Name == "Classical");

        // Create 100 albums - 10 per genre
        var albums = new List<Album>
        {
            // Rock - 10 albums
            new() { Title = "Thunder Road", GenreId = genreRock.GenreId, ArtistId = artists[0].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Electric Dreams", GenreId = genreRock.GenreId, ArtistId = artists[1].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Highway to Tomorrow", GenreId = genreRock.GenreId, ArtistId = artists[2].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Rebel Heart", GenreId = genreRock.GenreId, ArtistId = artists[3].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Crimson Sky", GenreId = genreRock.GenreId, ArtistId = artists[4].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Sonic Revolution", GenreId = genreRock.GenreId, ArtistId = artists[5].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Wild Nights", GenreId = genreRock.GenreId, ArtistId = artists[6].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Phoenix Rising", GenreId = genreRock.GenreId, ArtistId = artists[7].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Neon Lights", GenreId = genreRock.GenreId, ArtistId = artists[8].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Born to Rock", GenreId = genreRock.GenreId, ArtistId = artists[9].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Jazz - 10 albums
            new() { Title = "Smooth Midnight", GenreId = genreJazz.GenreId, ArtistId = artists[10].ArtistId, Price = 13.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Blue Note Sessions", GenreId = genreJazz.GenreId, ArtistId = artists[11].ArtistId, Price = 14.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Swingin' at the Savoy", GenreId = genreJazz.GenreId, ArtistId = artists[12].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Saxophone Serenade", GenreId = genreJazz.GenreId, ArtistId = artists[13].ArtistId, Price = 13.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Urban Groove", GenreId = genreJazz.GenreId, ArtistId = artists[14].ArtistId, Price = 14.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Cool Cat Blues", GenreId = genreJazz.GenreId, ArtistId = artists[10].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Velvet Underground", GenreId = genreJazz.GenreId, ArtistId = artists[11].ArtistId, Price = 13.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Night Train", GenreId = genreJazz.GenreId, ArtistId = artists[12].ArtistId, Price = 14.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Bebop Revolution", GenreId = genreJazz.GenreId, ArtistId = artists[13].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Harlem Nights", GenreId = genreJazz.GenreId, ArtistId = artists[14].ArtistId, Price = 13.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Metal - 10 albums
            new() { Title = "Steel Vengeance", GenreId = genreMetal.GenreId, ArtistId = artists[15].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Iron Throne", GenreId = genreMetal.GenreId, ArtistId = artists[16].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Thunder Strike", GenreId = genreMetal.GenreId, ArtistId = artists[17].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Chaos Theory", GenreId = genreMetal.GenreId, ArtistId = artists[18].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Death's Door", GenreId = genreMetal.GenreId, ArtistId = artists[19].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Metallic Storm", GenreId = genreMetal.GenreId, ArtistId = artists[15].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Warrior's Anthem", GenreId = genreMetal.GenreId, ArtistId = artists[16].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Eternal Fire", GenreId = genreMetal.GenreId, ArtistId = artists[17].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Blackened Sky", GenreId = genreMetal.GenreId, ArtistId = artists[18].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Hammer of the Gods", GenreId = genreMetal.GenreId, ArtistId = artists[19].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Alternative - 10 albums
            new() { Title = "Indie Sunrise", GenreId = genreAlternative.GenreId, ArtistId = artists[20].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Alternative Universe", GenreId = genreAlternative.GenreId, ArtistId = artists[21].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Lost in Translation", GenreId = genreAlternative.GenreId, ArtistId = artists[22].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Canvas of Dreams", GenreId = genreAlternative.GenreId, ArtistId = artists[23].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Echo Park", GenreId = genreAlternative.GenreId, ArtistId = artists[24].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Broken Strings", GenreId = genreAlternative.GenreId, ArtistId = artists[20].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Wanderlust", GenreId = genreAlternative.GenreId, ArtistId = artists[21].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Moonlight Drive", GenreId = genreAlternative.GenreId, ArtistId = artists[22].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Parallel Lines", GenreId = genreAlternative.GenreId, ArtistId = artists[23].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Underground Sound", GenreId = genreAlternative.GenreId, ArtistId = artists[24].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Disco - 10 albums
            new() { Title = "Disco Fever", GenreId = genreDisco.GenreId, ArtistId = artists[25].ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Glitter & Gold", GenreId = genreDisco.GenreId, ArtistId = artists[26].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Funky Town", GenreId = genreDisco.GenreId, ArtistId = artists[27].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Saturday Night", GenreId = genreDisco.GenreId, ArtistId = artists[28].ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Studio Magic", GenreId = genreDisco.GenreId, ArtistId = artists[29].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Boogie Wonderland", GenreId = genreDisco.GenreId, ArtistId = artists[25].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Dance Floor Magic", GenreId = genreDisco.GenreId, ArtistId = artists[26].ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Groove Machine", GenreId = genreDisco.GenreId, ArtistId = artists[27].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Midnight Dancer", GenreId = genreDisco.GenreId, ArtistId = artists[28].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Sparkle & Shine", GenreId = genreDisco.GenreId, ArtistId = artists[29].ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Blues - 10 albums
            new() { Title = "Delta Morning", GenreId = genreBlues.GenreId, ArtistId = artists[30].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Memphis Soul", GenreId = genreBlues.GenreId, ArtistId = artists[31].ArtistId, Price = 13.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Chicago Night", GenreId = genreBlues.GenreId, ArtistId = artists[32].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Muddy Road", GenreId = genreBlues.GenreId, ArtistId = artists[33].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Crossroads Journey", GenreId = genreBlues.GenreId, ArtistId = artists[34].ArtistId, Price = 13.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Highway Blues", GenreId = genreBlues.GenreId, ArtistId = artists[30].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Smokestack Lightning", GenreId = genreBlues.GenreId, ArtistId = artists[31].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Hoochie Coochie", GenreId = genreBlues.GenreId, ArtistId = artists[32].ArtistId, Price = 13.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Born Under a Bad Sign", GenreId = genreBlues.GenreId, ArtistId = artists[33].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Blues Power", GenreId = genreBlues.GenreId, ArtistId = artists[34].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Latin - 10 albums
            new() { Title = "Salsa Heat", GenreId = genreLatin.GenreId, ArtistId = artists[35].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Tropical Paradise", GenreId = genreLatin.GenreId, ArtistId = artists[36].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Latin Soul", GenreId = genreLatin.GenreId, ArtistId = artists[37].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Mambo Magic", GenreId = genreLatin.GenreId, ArtistId = artists[38].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Bossa Nova Nights", GenreId = genreLatin.GenreId, ArtistId = artists[39].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Fiesta Latina", GenreId = genreLatin.GenreId, ArtistId = artists[35].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Ritmo Caliente", GenreId = genreLatin.GenreId, ArtistId = artists[36].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Tango Passion", GenreId = genreLatin.GenreId, ArtistId = artists[37].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Cumbia Dreams", GenreId = genreLatin.GenreId, ArtistId = artists[38].ArtistId, Price = 12.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Merengue Madness", GenreId = genreLatin.GenreId, ArtistId = artists[39].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Reggae - 10 albums
            new() { Title = "Kingston Sunrise", GenreId = genreReggae.GenreId, ArtistId = artists[40].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Roots & Culture", GenreId = genreReggae.GenreId, ArtistId = artists[41].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Island Breeze", GenreId = genreReggae.GenreId, ArtistId = artists[42].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Rastaman Vibration", GenreId = genreReggae.GenreId, ArtistId = artists[43].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "One Love", GenreId = genreReggae.GenreId, ArtistId = artists[44].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Caribbean Soul", GenreId = genreReggae.GenreId, ArtistId = artists[40].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Dub Revolution", GenreId = genreReggae.GenreId, ArtistId = artists[41].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Trenchtown Rock", GenreId = genreReggae.GenreId, ArtistId = artists[42].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Positive Vibes", GenreId = genreReggae.GenreId, ArtistId = artists[43].ArtistId, Price = 11.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Jah Bless", GenreId = genreReggae.GenreId, ArtistId = artists[44].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Pop - 10 albums
            new() { Title = "Pop Sensation", GenreId = genrePop.GenreId, ArtistId = artists[45].ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Chart Domination", GenreId = genrePop.GenreId, ArtistId = artists[46].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Catchy Hooks", GenreId = genrePop.GenreId, ArtistId = artists[47].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Radio Ready", GenreId = genrePop.GenreId, ArtistId = artists[48].ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Mainstream Dreams", GenreId = genrePop.GenreId, ArtistId = artists[49].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Hit Machine", GenreId = genrePop.GenreId, ArtistId = artists[45].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Summer Vibes", GenreId = genrePop.GenreId, ArtistId = artists[46].ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Feel Good Music", GenreId = genrePop.GenreId, ArtistId = artists[47].ArtistId, Price = 9.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Pop Revolution", GenreId = genrePop.GenreId, ArtistId = artists[48].ArtistId, Price = 10.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Top 40 Hits", GenreId = genrePop.GenreId, ArtistId = artists[49].ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },

            // Classical - 10 albums
            new() { Title = "Symphony No. 1", GenreId = genreClassical.GenreId, ArtistId = artists[50].ArtistId, Price = 14.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Chamber Works", GenreId = genreClassical.GenreId, ArtistId = artists[51].ArtistId, Price = 15.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Baroque Collection", GenreId = genreClassical.GenreId, ArtistId = artists[52].ArtistId, Price = 16.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Piano Sonatas", GenreId = genreClassical.GenreId, ArtistId = artists[53].ArtistId, Price = 14.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "String Quartets", GenreId = genreClassical.GenreId, ArtistId = artists[54].ArtistId, Price = 15.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Concerto Collection", GenreId = genreClassical.GenreId, ArtistId = artists[50].ArtistId, Price = 16.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Orchestral Masterpieces", GenreId = genreClassical.GenreId, ArtistId = artists[51].ArtistId, Price = 14.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Romantic Era", GenreId = genreClassical.GenreId, ArtistId = artists[52].ArtistId, Price = 15.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Modern Compositions", GenreId = genreClassical.GenreId, ArtistId = artists[53].ArtistId, Price = 16.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Virtuoso Performances", GenreId = genreClassical.GenreId, ArtistId = artists[54].ArtistId, Price = 14.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" }
        };

        await context.Albums.AddRangeAsync(albums);
        await context.SaveChangesAsync();

        // Generate album art PNGs if webRootPath is available
        if (!string.IsNullOrEmpty(webRootPath))
        {
            var genreMap = await context.Genres.ToDictionaryAsync(g => g.GenreId, g => g.Name);
            var genreCounter = new Dictionary<int, int>();

            foreach (var album in albums)
            {
                if (!genreCounter.TryGetValue(album.GenreId, out var count))
                    count = 0;
                genreCounter[album.GenreId] = count + 1;

                var genreName = genreMap.GetValueOrDefault(album.GenreId, "Rock");
                var fileName = $"album-{album.AlbumId}.png";
                var filePath = Path.Combine(webRootPath, "Images", "AlbumArt", fileName);

                AlbumArtGenerator.GenerateAlbumArt(filePath, genreName, count);

                album.AlbumArtUrl = $"/Images/AlbumArt/{fileName}";
            }

            await context.SaveChangesAsync();
        }
    }
}
