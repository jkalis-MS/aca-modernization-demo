using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;

namespace MvcMusicStore.Models
{
    /// <summary>
    /// In-memory data store to replace SQL database
    /// </summary>
    public class InMemoryDataStore
    {
        private static readonly Lazy<InMemoryDataStore> _instance = new Lazy<InMemoryDataStore>(() => new InMemoryDataStore());
        
        public static InMemoryDataStore Instance => _instance.Value;

        private int _nextAlbumId = 1;
        private int _nextGenreId = 1;
        private int _nextArtistId = 1;
        private int _nextCartRecordId = 1;
        private int _nextOrderId = 1;
        private int _nextOrderDetailId = 1;

        public ConcurrentDictionary<int, Album> Albums { get; private set; }
        public ConcurrentDictionary<int, Genre> Genres { get; private set; }
        public ConcurrentDictionary<int, Artist> Artists { get; private set; }
        public ConcurrentDictionary<int, Cart> Carts { get; private set; }
        public ConcurrentDictionary<int, Order> Orders { get; private set; }
        public ConcurrentDictionary<int, OrderDetail> OrderDetails { get; private set; }

        private InMemoryDataStore()
        {
            Albums = new ConcurrentDictionary<int, Album>();
            Genres = new ConcurrentDictionary<int, Genre>();
            Artists = new ConcurrentDictionary<int, Artist>();
            Carts = new ConcurrentDictionary<int, Cart>();
            Orders = new ConcurrentDictionary<int, Order>();
            OrderDetails = new ConcurrentDictionary<int, OrderDetail>();
            
            InitializeSampleData();
        }

        public int GetNextAlbumId() => _nextAlbumId++;
        public int GetNextGenreId() => _nextGenreId++;
        public int GetNextArtistId() => _nextArtistId++;
        public int GetNextCartRecordId() => _nextCartRecordId++;
        public int GetNextOrderId() => _nextOrderId++;
        public int GetNextOrderDetailId() => _nextOrderDetailId++;

        private void InitializeSampleData()
        {
            const string imgUrl = "~/Images/placeholder.png";

            var genres = AddGenres();
            var artists = AddArtists();
            AddAlbums(imgUrl, genres, artists);
        }

        private List<Genre> AddGenres()
        {
            var genres = new List<Genre>
            {
                new Genre { GenreId = GetNextGenreId(), Name = "Pop" },
                new Genre { GenreId = GetNextGenreId(), Name = "Rock" },
                new Genre { GenreId = GetNextGenreId(), Name = "Jazz" },
                new Genre { GenreId = GetNextGenreId(), Name = "Metal" },
                new Genre { GenreId = GetNextGenreId(), Name = "Electronic" },
                new Genre { GenreId = GetNextGenreId(), Name = "Blues" },
                new Genre { GenreId = GetNextGenreId(), Name = "Latin" },
                new Genre { GenreId = GetNextGenreId(), Name = "Rap" },
                new Genre { GenreId = GetNextGenreId(), Name = "Classical" },
                new Genre { GenreId = GetNextGenreId(), Name = "Alternative" },
                new Genre { GenreId = GetNextGenreId(), Name = "Country" },
                new Genre { GenreId = GetNextGenreId(), Name = "R&B" },
                new Genre { GenreId = GetNextGenreId(), Name = "Indie" },
                new Genre { GenreId = GetNextGenreId(), Name = "Punk" },
                new Genre { GenreId = GetNextGenreId(), Name = "World" }
            };

            foreach (var genre in genres)
            {
                Genres[genre.GenreId] = genre;
            }

            return genres;
        }

        private List<Artist> AddArtists()
        {
            var artistNames = new List<string>
            {
                "AC/DC", "Accept", "Aerosmith", "Alanis Morissette", "Alice in Chains",
                "Antônio Carlos Jobim", "Apocalyptica", "Audioslave", "BackBeat",
                "Billy Cobham", "Black Label Society", "Black Sabbath", "Body Count",
                "Bruce Dickinson", "Buddy Guy", "Caetano Veloso", "Chico Buarque",
                "Chico Science & Nação Zumbi", "Cidade Negra", "Cláudio Zoli", "Various Artists",
                "Led Zeppelin", "Frank Zappa & Captain Beefheart", "Marcos Valle", "Milton Nascimento",
                "Azymuth", "Gilberto Gil", "João Gilberto", "Bebel Gilberto", "Jorge Ben Jor",
                "Metallica", "Queen", "Kiss", "Spyro Gyra", "The Who", "Van Halen",
                "Velvet Revolver", "Whitesnake", "Zeca Pagodinho", "The Office", "Dread Zeppelin",
                "Guns N' Roses", "Incognito", "Page & Plant", "Iron Maiden",
                "Jimi Hendrix", "Joe Satriani", "Jota Quest", "João Suplicy", "Elis Regina",
                "OS Paralamas Do Sucesso", "Men At Work", "Motörhead", "Marillion",
                "Marisa Monte", "Metallica", "Miles Davis", "Motörhead",
                "Mötley Crüe", "Nirvana", "Nine Inch Nails", "Oasis",
                "Opeth", "Os Mutantes", "Ozzy Osbourne", "Ozzy Osbourne", "Pearl Jam",
                "Pink Floyd", "Planet Hemp", "R.E.M.", "Ramones", "Red Hot Chili Peppers",
                "Rush", "Simply Red", "Skank", "Smashing Pumpkins", "Soundgarden",
                "Stevie Ray Vaughan", "Stone Temple Pilots", "System Of A Down", "Terry Bozzio, Tony Levin & Steve Stevens",
                "The Black Crowes", "The Clash", "The Cult", "The Cure", "The Doors",
                "The Police", "The Rolling Stones", "The Tea Party", "The Beatles",
                "Tool", "U2", "UB40", "Deftones", "Lenny Kravitz",
                "Santana", "Foo Fighters", "Creedence Clearwater Revival", "Jamiroquai", "Faith No More",
                "Def Leppard", "Deep Purple", "Dio", "Dream Theater", "Godsmack",
                "Megadeth", "Scorpions", "Sepultura", "Slayer", "??????",
                "???? ????????", "Legião Urbana", "Nega Gizza", "Norah Jones", "Sarah Brightman",
                "Scholars Baroque Ensemble", "Academy of St. Martin in the Fields & Sir Neville Marriner",
                "London Symphony Orchestra", "Royal Philharmonic Orchestra", "Yo-Yo Ma",
                "Eugene Ormandy", "Luciano Pavarotti", "Leonard Bernstein", "Boston Symphony Orchestra & Seiji Ozawa",
                "Aaron Copland & London Symphony Orchestra", "Chicago Symphony Orchestra", "Adrian Leaper & Doreen de Feis",
                "Chicago Symphony Orchestra & Fritz Reiner", "Sir Georg Solti & Wiener Philharmoniker", "Wilhelm Kempff",
                "Nicolaus Esterhazy Sinfonia", "Berliner Philharmoniker", "Yo-Yo Ma", "Britten Sinfonia, Ivor Bolton & Lesley Garrett",
                "Nash Ensemble", "Philip Glass Ensemble", "English Concert & Trevor Pinnock", "The King's Singers",
                "David Bowie", "Tears For Fears", "Duran Duran", "Pet Shop Boys",
                "Yehudi Menuhin", "Mela Tenenbaum, Pro Musica Prague & Richard Kapp", "Martin Roscoe",
                "Ton Koopman", "Wendy Carlos", "Michael Tilson Thomas", "Christopher O'Riley",
                "Fretwork", "Amy Winehouse", "Cássia Eller", "Seu Jorge", "Djavan",
                "Elba Ramalho", "Milton Nascimento", "Tim Maia", "Elis Regina",
                "Sergei Prokofiev & Yuri Temirkanov", "Göteborgs Symfoniker & Neeme Järvi", "Choir Of Westminster Abbey & Simon Preston",
                "Les Arts Florissants & William Christie", "The 12 Cellists of The Berlin Philharmonic", "Eminem",
                "Daft Punk", "Deadmau5", "Justice", "The Prodigy", "Amon Tobin",
                "Skrillex", "Paul Oakenfold", "Above & Beyond", "David Guetta", "Tiësto",
                "Armin van Buuren", "Eric Clapton", "B.B. King", "Buddy Guy", "Muddy Waters",
                "Robert Johnson", "Stevie Ray Vaughan & Double Trouble", "The Allman Brothers Band", "ZZ Top",
                "Blues Traveler", "John Mayer", "Coldplay", "Radiohead", "Muse",
                "Arctic Monkeys", "The Strokes", "Kings of Leon", "Alabama Shakes", "The Black Keys",
                "Jack Johnson", "Ben Harper", "G. Love & Special Sauce", "Mumford & Sons", "The Lumineers",
                "Of Monsters and Men", "Edward Sharpe & The Magnetic Zeros", "The Head and the Heart", "The Avett Brothers",
                "Ray Charles", "Aretha Franklin", "Marvin Gaye", "Al Green", "Otis Redding",
                "Sam Cooke", "James Brown", "Stevie Wonder", "Michael Jackson", "Prince",
                "Whitney Houston", "Tina Turner", "Anita Baker", "Luther Vandross",
                "Boyz II Men", "TLC", "Destiny's Child", "Alicia Keys", "John Legend",
                "Frank Sinatra", "Ella Fitzgerald", "Billie Holiday", "Louis Armstrong", "Nat King Cole",
                "Duke Ellington", "Count Basie", "Thelonious Monk", "Charlie Parker", "John Coltrane",
                "Herbie Hancock", "Chick Corea", "Weather Report", "Pat Metheny", "Keith Jarrett",
                "Brad Mehldau", "Esbjörn Svensson Trio", "Medeski Martin & Wood", "Soulive", "Robert Glasper",
                "Kamasi Washington", "Snarky Puppy", "Avishai Cohen", "GoGo Penguin", "Alfa Mist",
                "Hank Williams", "Johnny Cash", "Patsy Cline", "Willie Nelson", "Waylon Jennings",
                "Merle Haggard", "George Jones", "Tammy Wynette", "Loretta Lynn", "Dolly Parton",
                "Kenny Rogers", "Garth Brooks", "Shania Twain", "Faith Hill", "Tim McGraw",
                "Keith Urban", "Brad Paisley", "Carrie Underwood", "Miranda Lambert", "Luke Bryan",
                "Blake Shelton", "Jason Aldean", "Florida Georgia Line", "Dan + Shay", "Kacey Musgraves",
                "Grandmaster Flash", "Run DMC", "Public Enemy", "N.W.A", "Ice-T",
                "LL Cool J", "Beastie Boys", "A Tribe Called Quest", "De La Soul", "Gang Starr",
                "Wu-Tang Clan", "Nas", "The Notorious B.I.G.", "Tupac", "Jay-Z",
                "Dr. Dre", "Snoop Dogg", "OutKast", "Missy Elliott", "Lauryn Hill",
                "Kanye West", "Kendrick Lamar", "J. Cole", "Drake", "Lil Wayne",
                "Rick Ross", "Teflon Don", "Nujabes", "M-Flo", "PSY",
                "Sufjan Stevens", "Modest Mouse", "The Decemberists", "Arcade Fire", "The National",
                "Bon Iver", "Fleet Foxes", "Grizzly Bear", "Animal Collective", "Vampire Weekend",
                "MGMT", "Tame Impala", "The xx", "Alt-J", "Glass Animals",
                "The 1975", "Twenty One Pilots", "Imagine Dragons", "Cage The Elephant", "Foster The People"
            };

            var artists = new List<Artist>();
            foreach (var name in artistNames)
            {
                var artist = new Artist
                {
                    ArtistId = GetNextArtistId(),
                    Name = name
                };
                Artists[artist.ArtistId] = artist;
                artists.Add(artist);
            }

            return artists;
        }

        private void AddAlbums(string imgUrl, List<Genre> genres, List<Artist> artists)
        {
            // Create a sampling of albums from the original data
            var albumData = new[]
            {
                new { Title = "The Best Of The Men At Work", GenreName = "Pop", ArtistName = "Men At Work", Price = 8.99M },
                new { Title = "...And Justice For All", GenreName = "Metal", ArtistName = "Metallica", Price = 8.99M },
                new { Title = "Black Light Syndrome", GenreName = "Rock", ArtistName = "Terry Bozzio, Tony Levin & Steve Stevens", Price = 8.99M },
                new { Title = "10,000 Days", GenreName = "Rock", ArtistName = "Tool", Price = 8.99M },
                new { Title = "Abbey Road", GenreName = "Rock", ArtistName = "The Beatles", Price = 8.99M },
                new { Title = "Ace Of Spades", GenreName = "Metal", ArtistName = "Motörhead", Price = 8.99M },
                new { Title = "Achtung Baby", GenreName = "Rock", ArtistName = "U2", Price = 8.99M },
                new { Title = "Appetite for Destruction", GenreName = "Rock", ArtistName = "Guns N' Roses", Price = 8.99M },
                new { Title = "Are You Experienced?", GenreName = "Rock", ArtistName = "Jimi Hendrix", Price = 8.99M },
                new { Title = "Dark Side of the Moon", GenreName = "Rock", ArtistName = "Pink Floyd", Price = 8.99M },
                new { Title = "Death Magnetic", GenreName = "Metal", ArtistName = "Metallica", Price = 8.99M },
                new { Title = "Led Zeppelin I", GenreName = "Rock", ArtistName = "Led Zeppelin", Price = 8.99M },
                new { Title = "Led Zeppelin II", GenreName = "Rock", ArtistName = "Led Zeppelin", Price = 8.99M },
                new { Title = "Led Zeppelin III", GenreName = "Rock", ArtistName = "Led Zeppelin", Price = 8.99M },
                new { Title = "Nevermind", GenreName = "Rock", ArtistName = "Nirvana", Price = 8.99M },
                new { Title = "The Joshua Tree", GenreName = "Rock", ArtistName = "U2", Price = 8.99M },
                new { Title = "The Wall", GenreName = "Rock", ArtistName = "Pink Floyd", Price = 8.99M },
                new { Title = "Master of Puppets", GenreName = "Metal", ArtistName = "Metallica", Price = 8.99M },
                new { Title = "Ride The Lightning", GenreName = "Metal", ArtistName = "Metallica", Price = 8.99M },
                new { Title = "Kill 'Em All", GenreName = "Metal", ArtistName = "Metallica", Price = 8.99M },
                new { Title = "Greatest Hits I", GenreName = "Rock", ArtistName = "Queen", Price = 8.99M },
                new { Title = "Greatest Hits II", GenreName = "Rock", ArtistName = "Queen", Price = 8.99M },
                new { Title = "The Number of The Beast", GenreName = "Metal", ArtistName = "Iron Maiden", Price = 8.99M },
                new { Title = "Powerslave", GenreName = "Metal", ArtistName = "Iron Maiden", Price = 8.99M },
                new { Title = "IV", GenreName = "Rock", ArtistName = "Led Zeppelin", Price = 8.99M },
                new { Title = "Houses Of The Holy", GenreName = "Rock", ArtistName = "Led Zeppelin", Price = 8.99M },
                new { Title = "Physical Graffiti", GenreName = "Rock", ArtistName = "Led Zeppelin", Price = 8.99M },
                new { Title = "In Through The Out Door", GenreName = "Rock", ArtistName = "Led Zeppelin", Price = 8.99M },
                new { Title = "Ten", GenreName = "Rock", ArtistName = "Pearl Jam", Price = 8.99M },
                new { Title = "Vs.", GenreName = "Rock", ArtistName = "Pearl Jam", Price = 8.99M },
                new { Title = "Kind of Blue", GenreName = "Jazz", ArtistName = "Miles Davis", Price = 8.99M },
                new { Title = "Come Away With Me", GenreName = "Jazz", ArtistName = "Norah Jones", Price = 8.99M },
                new { Title = "Blue Moods", GenreName = "Jazz", ArtistName = "Incognito", Price = 8.99M },
                new { Title = "The Chronic", GenreName = "Rap", ArtistName = "Dr. Dre", Price = 8.99M },
                new { Title = "Recovery [Explicit]", GenreName = "Rap", ArtistName = "Eminem", Price = 8.99M },
                new { Title = "4x4=12 ", GenreName = "Electronic", ArtistName = "Deadmau5", Price = 8.99M },
                new { Title = "Album Title Goes Here", GenreName = "Electronic", ArtistName = "Deadmau5", Price = 8.99M },
                new { Title = "Alive 2007", GenreName = "Electronic", ArtistName = "Daft Punk", Price = 8.99M },
                new { Title = "Homework", GenreName = "Electronic", ArtistName = "Daft Punk", Price = 8.99M },
                new { Title = "Cross", GenreName = "Electronic", ArtistName = "Justice", Price = 8.99M },
                new { Title = "Unplugged", GenreName = "Blues", ArtistName = "Eric Clapton", Price = 8.99M },
                new { Title = "Texas Flood", GenreName = "Blues", ArtistName = "Stevie Ray Vaughan", Price = 8.99M },
                new { Title = "Four", GenreName = "Blues", ArtistName = "Blues Traveler", Price = 8.99M },
                new { Title = "Room for Squares", GenreName = "Pop", ArtistName = "John Mayer", Price = 8.99M },
                new { Title = "X&Y", GenreName = "Rock", ArtistName = "Coldplay", Price = 8.99M },
                new { Title = "A Rush of Blood to the Head", GenreName = "Rock", ArtistName = "Coldplay", Price = 8.99M },
                new { Title = "In Rainbows", GenreName = "Rock", ArtistName = "Radiohead", Price = 8.99M },
                new { Title = "OK Computer", GenreName = "Rock", ArtistName = "Radiohead", Price = 8.99M },
                new { Title = "Babel", GenreName = "Alternative", ArtistName = "Mumford & Sons", Price = 8.99M },
                new { Title = "The Lumineers", GenreName = "Rock", ArtistName = "The Lumineers", Price = 8.99M },
                new { Title = "El Camino", GenreName = "Rock", ArtistName = "The Black Keys", Price = 8.99M }
            };

            foreach (var data in albumData)
            {
                var genre = genres.FirstOrDefault(g => g.Name == data.GenreName);
                var artist = artists.FirstOrDefault(a => a.Name == data.ArtistName);

                if (genre != null && artist != null)
                {
                    var album = new Album
                    {
                        AlbumId = GetNextAlbumId(),
                        Title = data.Title,
                        GenreId = genre.GenreId,
                        ArtistId = artist.ArtistId,
                        Price = data.Price,
                        AlbumArtUrl = imgUrl,
                        Genre = genre,
                        Artist = artist
                    };
                    Albums[album.AlbumId] = album;
                }
            }
        }

        public void SaveChanges()
        {
            // No-op for in-memory store - changes are immediate
        }
    }
}
