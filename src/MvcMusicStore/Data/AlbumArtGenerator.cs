using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;

namespace MvcMusicStore.Data;

/// <summary>
/// Generates simple PNG album art images programmatically without external dependencies.
/// Each image is a solid color block with genre-based color palettes.
/// </summary>
public static class AlbumArtGenerator
{
    private static readonly Dictionary<string, (byte R, byte G, byte B)[]> GenreColors = new()
    {
        ["Rock"] = [
            (220, 50, 50), (180, 30, 30), (200, 60, 40), (160, 40, 40), (230, 70, 50),
            (190, 45, 35), (210, 55, 45), (170, 35, 35), (225, 65, 55), (195, 50, 40)
        ],
        ["Jazz"] = [
            (50, 50, 150), (40, 40, 130), (60, 60, 170), (70, 50, 140), (45, 55, 160),
            (55, 45, 135), (65, 65, 155), (50, 60, 145), (75, 55, 165), (60, 50, 150)
        ],
        ["Metal"] = [
            (60, 60, 60), (40, 40, 40), (80, 80, 80), (50, 50, 50), (70, 70, 70),
            (45, 45, 45), (55, 55, 55), (65, 65, 65), (75, 75, 75), (85, 85, 85)
        ],
        ["Alternative"] = [
            (100, 180, 100), (80, 160, 80), (120, 200, 120), (90, 170, 90), (110, 190, 110),
            (85, 165, 85), (95, 175, 95), (105, 185, 105), (115, 195, 115), (125, 205, 125)
        ],
        ["Disco"] = [
            (230, 150, 50), (240, 160, 60), (220, 140, 40), (250, 170, 70), (210, 130, 30),
            (235, 155, 55), (225, 145, 45), (245, 165, 65), (215, 135, 35), (255, 175, 75)
        ],
        ["Blues"] = [
            (30, 80, 160), (25, 70, 140), (35, 90, 180), (20, 75, 150), (40, 85, 170),
            (28, 78, 155), (33, 83, 165), (23, 73, 145), (38, 88, 175), (43, 93, 185)
        ],
        ["Latin"] = [
            (230, 100, 50), (220, 90, 40), (240, 110, 60), (210, 80, 30), (250, 120, 70),
            (225, 95, 45), (235, 105, 55), (215, 85, 35), (245, 115, 65), (255, 125, 75)
        ],
        ["Reggae"] = [
            (60, 160, 60), (200, 180, 40), (220, 60, 40), (50, 150, 50), (190, 170, 30),
            (210, 50, 30), (70, 170, 70), (180, 160, 50), (55, 155, 55), (195, 175, 35)
        ],
        ["Pop"] = [
            (220, 100, 200), (200, 80, 180), (240, 120, 220), (210, 90, 190), (230, 110, 210),
            (205, 85, 185), (215, 95, 195), (225, 105, 205), (235, 115, 215), (245, 125, 225)
        ],
        ["Classical"] = [
            (180, 160, 120), (170, 150, 110), (190, 170, 130), (160, 140, 100), (200, 180, 140),
            (175, 155, 115), (185, 165, 125), (165, 145, 105), (195, 175, 135), (205, 185, 145)
        ]
    };

    /// <summary>
    /// Generates a simple PNG file with a two-tone gradient pattern.
    /// The image is 100x100 pixels with a genre-based color scheme.
    /// </summary>
    public static void GenerateAlbumArt(string outputPath, string genreName, int colorIndex)
    {
        var dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        var colors = GenreColors.GetValueOrDefault(genreName, GenreColors["Rock"]);
        var idx = Math.Abs(colorIndex) % colors.Length;
        var (r, g, b) = colors[idx];

        // Secondary color for the diagonal pattern
        var r2 = (byte)Math.Min(255, r + 40);
        var g2 = (byte)Math.Min(255, g + 40);
        var b2 = (byte)Math.Min(255, b + 40);

        const int width = 100;
        const int height = 100;

        var pngBytes = CreatePng(width, height, r, g, b, r2, g2, b2);
        File.WriteAllBytes(outputPath, pngBytes);
    }

    private static byte[] CreatePng(int width, int height, byte r1, byte g1, byte b1, byte r2, byte g2, byte b2)
    {
        using var ms = new MemoryStream();
        // PNG Signature
        ms.Write([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

        // IHDR chunk
        WriteChunk(ms, "IHDR", writer =>
        {
            writer.Write(ToBigEndian(width));
            writer.Write(ToBigEndian(height));
            writer.Write((byte)8); // bit depth
            writer.Write((byte)2); // color type: RGB
            writer.Write((byte)0); // compression
            writer.Write((byte)0); // filter
            writer.Write((byte)0); // interlace
        });

        // IDAT chunk - image data
        var rawData = new byte[height * (1 + width * 3)]; // filter byte + RGB per pixel per row
        for (int y = 0; y < height; y++)
        {
            int rowStart = y * (1 + width * 3);
            rawData[rowStart] = 0; // filter: None

            for (int x = 0; x < width; x++)
            {
                int pixelOffset = rowStart + 1 + x * 3;

                // Create a diagonal split pattern
                float t = (float)(x + y) / (width + height);
                rawData[pixelOffset + 0] = (byte)(r1 + (r2 - r1) * t);
                rawData[pixelOffset + 1] = (byte)(g1 + (g2 - g1) * t);
                rawData[pixelOffset + 2] = (byte)(b1 + (b2 - b1) * t);
            }
        }

        // Compress the raw data using deflate (zlib)
        byte[] compressedData;
        using (var compressedStream = new MemoryStream())
        {
            // zlib header
            compressedStream.Write([(byte)0x78, (byte)0x01]);

            using (var deflate = new DeflateStream(compressedStream, CompressionLevel.Fastest, leaveOpen: true))
            {
                deflate.Write(rawData, 0, rawData.Length);
            }

            // Adler-32 checksum
            uint adler = Adler32(rawData);
            compressedStream.Write(ToBigEndian((int)adler));

            compressedData = compressedStream.ToArray();
        }

        WriteChunk(ms, "IDAT", writer =>
        {
            writer.Write(compressedData);
        });

        // IEND chunk
        WriteChunk(ms, "IEND", _ => { });

        return ms.ToArray();
    }

    private static void WriteChunk(Stream stream, string type, Action<BinaryWriter> writeData)
    {
        using var dataStream = new MemoryStream();
        using (var writer = new BinaryWriter(dataStream, System.Text.Encoding.ASCII, leaveOpen: true))
        {
            writeData(writer);
        }

        var data = dataStream.ToArray();
        var typeBytes = System.Text.Encoding.ASCII.GetBytes(type);

        // Length
        stream.Write(ToBigEndian(data.Length));

        // Type + Data (for CRC calculation)
        var crcData = new byte[typeBytes.Length + data.Length];
        Array.Copy(typeBytes, 0, crcData, 0, typeBytes.Length);
        Array.Copy(data, 0, crcData, typeBytes.Length, data.Length);

        stream.Write(typeBytes);
        stream.Write(data);

        // CRC
        uint crc = Crc32(crcData);
        stream.Write(ToBigEndian((int)crc));
    }

    private static byte[] ToBigEndian(int value)
    {
        var bytes = BitConverter.GetBytes(value);
        if (BitConverter.IsLittleEndian)
            Array.Reverse(bytes);
        return bytes;
    }

    private static uint Adler32(byte[] data)
    {
        uint a = 1, b = 0;
        foreach (byte d in data)
        {
            a = (a + d) % 65521;
            b = (b + a) % 65521;
        }
        return (b << 16) | a;
    }

    private static readonly uint[] Crc32Table = GenerateCrc32Table();

    private static uint[] GenerateCrc32Table()
    {
        var table = new uint[256];
        for (uint i = 0; i < 256; i++)
        {
            uint c = i;
            for (int j = 0; j < 8; j++)
            {
                if ((c & 1) != 0)
                    c = 0xEDB88320 ^ (c >> 1);
                else
                    c >>= 1;
            }
            table[i] = c;
        }
        return table;
    }

    private static uint Crc32(byte[] data)
    {
        uint crc = 0xFFFFFFFF;
        foreach (byte b in data)
        {
            crc = Crc32Table[(crc ^ b) & 0xFF] ^ (crc >> 8);
        }
        return crc ^ 0xFFFFFFFF;
    }
}
