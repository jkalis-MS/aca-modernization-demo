using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using MvcMusicStore.Models;

namespace MvcMusicStore.Data;

public static class DbSeeder
{
    public static async Task RecreateAndSeedAsync(MusicStoreEntities context, ILogger logger)
    {
        try
        {
            logger.LogInformation("Dropping and recreating database...");
            await context.Database.EnsureDeletedAsync();
            await context.Database.EnsureCreatedAsync();
            
            logger.LogInformation("Seeding database with sample data...");
            await SeedDataAsync(context);
            
            logger.LogInformation("Database recreated and seeded successfully.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "An error occurred while recreating and seeding the database.");
            throw;
        }
    }

    public static async Task SeedAsync(MusicStoreEntities context)
    {
        // Check if database already has data
        if (await context.Albums.AnyAsync())
        {
            return; // Database has been seeded
        }

        await SeedDataAsync(context);
    }

    private static async Task SeedDataAsync(MusicStoreEntities context)
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

        var artists = new List<Artist>
        {
            new() { Name = "AC/DC" },
            new() { Name = "Accept" },
            new() { Name = "Aerosmith" },
            new() { Name = "Alanis Morissette" },
            new() { Name = "Alice In Chains" },
            new() { Name = "Audioslave" },
            new() { Name = "Black Sabbath" },
            new() { Name = "Deep Purple" },
            new() { Name = "Eric Clapton" },
            new() { Name = "Faith No More" },
            new() { Name = "Foo Fighters" },
            new() { Name = "Guns N' Roses" },
            new() { Name = "Iron Maiden" },
            new() { Name = "Led Zeppelin" },
            new() { Name = "Lenny Kravitz" },
            new() { Name = "Metallica" },
            new() { Name = "Nirvana" },
            new() { Name = "Ozzy Osbourne" },
            new() { Name = "Pearl Jam" },
            new() { Name = "Pink Floyd" },
            new() { Name = "Queen" },
            new() { Name = "Red Hot Chili Peppers" },
            new() { Name = "U2" },
            new() { Name = "Van Halen" }
        };

        await context.Artists.AddRangeAsync(artists);
        await context.SaveChangesAsync();

        // Reload genres and artists with their IDs from database
        var genreRock = await context.Genres.FirstAsync(g => g.Name == "Rock");
        var genreMetal = await context.Genres.FirstAsync(g => g.Name == "Metal");
        var genreJazz = await context.Genres.FirstAsync(g => g.Name == "Jazz");
        var genreBlues = await context.Genres.FirstAsync(g => g.Name == "Blues");
        var genreAlternative = await context.Genres.FirstAsync(g => g.Name == "Alternative");

        var albums = new List<Album>
        {
            new() { Title = "For Those About To Rock We Salute You", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "AC/DC").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Let There Be Rock", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "AC/DC").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Balls to the Wall", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Accept").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Big Ones", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Aerosmith").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Jagged Little Pill", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Alanis Morissette").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Facelift", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Alice In Chains").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Revelations", GenreId = genreAlternative.GenreId, ArtistId = artists.First(a => a.Name == "Audioslave").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Audioslave", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Audioslave").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Black Sabbath", GenreId = genreMetal.GenreId, ArtistId = artists.First(a => a.Name == "Black Sabbath").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Deep Purple In Rock", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Deep Purple").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Machine Head", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Deep Purple").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Unplugged", GenreId = genreBlues.GenreId, ArtistId = artists.First(a => a.Name == "Eric Clapton").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "King For A Day Fool For A Lifetime", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Faith No More").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "In Your Honor [Disc 1]", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Foo Fighters").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "The Colour And The Shape", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Foo Fighters").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Appetite for Destruction", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Guns N' Roses").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Use Your Illusion I", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Guns N' Roses").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Use Your Illusion II", GenreId = genreMetal.GenreId, ArtistId = artists.First(a => a.Name == "Guns N' Roses").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "The Number of The Beast", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Iron Maiden").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Fear Of The Dark", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Iron Maiden").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Led Zeppelin I", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Led Zeppelin").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Led Zeppelin II", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Led Zeppelin").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Led Zeppelin III", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Led Zeppelin").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "IV", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Led Zeppelin").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Greatest Hits", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Lenny Kravitz").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "...And Justice For All", GenreId = genreMetal.GenreId, ArtistId = artists.First(a => a.Name == "Metallica").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Black Album", GenreId = genreMetal.GenreId, ArtistId = artists.First(a => a.Name == "Metallica").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Master Of Puppets", GenreId = genreMetal.GenreId, ArtistId = artists.First(a => a.Name == "Metallica").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Ride The Lightning", GenreId = genreMetal.GenreId, ArtistId = artists.First(a => a.Name == "Metallica").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Nevermind", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Nirvana").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Blizzard of Ozz", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Ozzy Osbourne").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "No More Tears (Remastered)", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Ozzy Osbourne").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Ten", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Pearl Jam").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Vs.", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Pearl Jam").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Dark Side Of The Moon", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Pink Floyd").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Greatest Hits I", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Queen").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Greatest Hits II", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Queen").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "News Of The World", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Queen").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "By The Way", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Red Hot Chili Peppers").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Californication", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Red Hot Chili Peppers").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Achtung Baby", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "U2").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "The Best Of 1980-1990", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "U2").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "War", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "U2").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Van Halen", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Van Halen").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" },
            new() { Title = "Diver Down", GenreId = genreRock.GenreId, ArtistId = artists.First(a => a.Name == "Van Halen").ArtistId, Price = 8.99M, AlbumArtUrl = "/Content/Images/placeholder.svg" }
        };

        await context.Albums.AddRangeAsync(albums);
        await context.SaveChangesAsync();
    }
}
