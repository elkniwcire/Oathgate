using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace SteamNite {
    // Windows ships winsqlite3.dll. Open launcher databases read-only, including their WAL.
    public static class NativeSqlite {
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern int sqlite3_open_v2(byte[] path, out IntPtr db, int flags, IntPtr vfs);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern int sqlite3_close(IntPtr db);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern int sqlite3_busy_timeout(IntPtr db, int milliseconds);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int length, out IntPtr stmt, IntPtr tail);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern int sqlite3_step(IntPtr stmt);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern int sqlite3_finalize(IntPtr stmt);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern int sqlite3_column_count(IntPtr stmt);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr sqlite3_column_name(IntPtr stmt, int index);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr sqlite3_column_text(IntPtr stmt, int index);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr sqlite3_errmsg(IntPtr db);
        static string Utf8(IntPtr ptr) {
            if (ptr == IntPtr.Zero) return null;
            int size = 0;
            while (Marshal.ReadByte(ptr, size) != 0) size++;
            byte[] bytes = new byte[size];
            Marshal.Copy(ptr, bytes, 0, size);
            return Encoding.UTF8.GetString(bytes);
        }
        public static List<Dictionary<string, string>> Read(string path, string sql) {
            IntPtr db = IntPtr.Zero, stmt = IntPtr.Zero;
            try {
                if (sqlite3_open_v2(Encoding.UTF8.GetBytes(path + "\0"), out db, 1, IntPtr.Zero) != 0)
                    throw new InvalidOperationException("Cannot read database: " + Utf8(sqlite3_errmsg(db)));
                sqlite3_busy_timeout(db, 1500);
                byte[] query = Encoding.UTF8.GetBytes(sql + "\0");
                if (sqlite3_prepare_v2(db, query, query.Length, out stmt, IntPtr.Zero) != 0)
                    throw new InvalidOperationException(Utf8(sqlite3_errmsg(db)));
                var rows = new List<Dictionary<string, string>>();
                int result;
                while ((result = sqlite3_step(stmt)) == 100) {
                    var row = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    for (int i = 0; i < sqlite3_column_count(stmt); i++)
                        row[Utf8(sqlite3_column_name(stmt, i))] = Utf8(sqlite3_column_text(stmt, i));
                    rows.Add(row);
                }
                if (result != 101) throw new InvalidOperationException(Utf8(sqlite3_errmsg(db)));
                return rows;
            } finally {
                if (stmt != IntPtr.Zero) sqlite3_finalize(stmt);
                if (db != IntPtr.Zero) sqlite3_close(db);
            }
        }
    }
}
