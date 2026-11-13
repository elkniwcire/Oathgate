using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace SteamNite {
    public sealed class ShortcutInfo {
        public string Index, Title, Exe, StartDir, LaunchOptions, ManagedId, Icon;
        public uint AppId;
    }
    public sealed class ShortcutDraft {
        public string Title, Exe, StartDir, LaunchOptions, ManagedId;
        public uint AppId;
    }
    // Existing records are copied byte-for-byte. Only new records are serialized.
    public sealed class SteamShortcuts {
        sealed class Node {
            public string Key, Text;
            public byte Type;
            public uint Number;
            public List<Node> Children;
            public int Start, End;
        }
        readonly byte[] source;
        readonly List<Node> entries;
        readonly int insertOffset;
        public readonly List<ShortcutInfo> Items = new List<ShortcutInfo>();
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        public SteamShortcuts(byte[] data) {
            if (data == null) data = new byte[] {0,115,104,111,114,116,99,117,116,115,0,8,8};
            source = data;
            using (var stream = new MemoryStream(data)) using (var reader = new BinaryReader(stream)) {
                if (reader.ReadByte() != 0 || String(reader) != "shortcuts") throw new InvalidDataException("Not a Steam shortcuts file.");
                entries = ReadObject(reader, 0);
                insertOffset = checked((int)stream.Position - 1);
                // Steam's binary VDF files have a root terminator and a file terminator.
                if (reader.ReadByte() != 8 || stream.Position != stream.Length) throw new InvalidDataException("Unexpected trailing VDF data.");
            }
            var indexes = new HashSet<string>();
            foreach (var entry in entries) {
                int number;
                if (entry.Type != 0 || !int.TryParse(entry.Key, out number) || number < 0 || !indexes.Add(entry.Key))
                    throw new InvalidDataException("Invalid or duplicate shortcut index.");
                Items.Add(new ShortcutInfo { Index=entry.Key, Title=Text(entry,"appname"), Exe=Text(entry,"exe"), StartDir=Text(entry,"StartDir"),
                    LaunchOptions=Text(entry,"LaunchOptions"), ManagedId=Text(entry,"DevkitGameID"), Icon=Text(entry,"icon"), AppId=Number(entry,"appid") });
            }
        }
        static string String(BinaryReader reader) {
            var bytes = new List<byte>();
            byte b;
            while ((b=reader.ReadByte()) != 0) { if (bytes.Count > 1024*1024) throw new InvalidDataException("VDF string is too long."); bytes.Add(b); }
            return Utf8.GetString(bytes.ToArray());
        }
        static List<Node> ReadObject(BinaryReader reader, int depth) {
            if (depth > 32) throw new InvalidDataException("VDF nesting is too deep.");
            var nodes = new List<Node>();
            while (true) {
                int start = checked((int)reader.BaseStream.Position);
                byte type = reader.ReadByte();
                if (type == 8) return nodes;
                var n = new Node {Type=type, Key=String(reader), Start=start};
                switch(type) {
                    case 0: n.Children=ReadObject(reader, depth+1); break;
                    case 1: n.Text=String(reader); break;
                    case 2: n.Number=reader.ReadUInt32(); break;
                    case 3: case 4: case 6: reader.ReadUInt32(); break;
                    case 7: case 10: reader.ReadUInt64(); break;
                    default: throw new InvalidDataException("Unsupported VDF field type " + type + "; no changes were made.");
                }
                n.End=checked((int)reader.BaseStream.Position); nodes.Add(n);
            }
        }
        static Node Field(Node node, string key) { return node.Children.FirstOrDefault(n => string.Equals(n.Key,key,StringComparison.OrdinalIgnoreCase)); }
        static string Text(Node node, string key) { var n=Field(node,key); return n != null && n.Type==1 ? n.Text : ""; }
        static uint Number(Node node,string key) { var n=Field(node,key); return n != null && n.Type==2 ? n.Number : 0; }
        static void CString(BinaryWriter writer,string value) {
            value = value ?? "";
            if (value.IndexOf('\0') >= 0) throw new InvalidDataException("Shortcut values cannot contain NUL characters.");
            writer.Write(Utf8.GetBytes(value)); writer.Write((byte)0);
        }
        static void Str(BinaryWriter w,string key,string value) { w.Write((byte)1); CString(w,key); CString(w,value); }
        static void Int(BinaryWriter w,string key,uint value) { w.Write((byte)2); CString(w,key); w.Write(value); }
        public static uint AppId(string exe,string title) {
            uint crc=0xffffffff;
            foreach(byte b in Utf8.GetBytes(exe+title)) {
                crc ^= b;
                for(int bit=0;bit<8;bit++) crc=(crc>>1)^((crc&1)!=0 ? 0xedb88320u : 0u);
            }
            return (crc^0xffffffffu)|0x80000000u;
        }
        public byte[] WithIcon(uint appId, string iconPath) {
            var matches=entries.Where(e=>Number(e,"appid")==appId).ToList();
            if(matches.Count!=1) throw new InvalidDataException("Expected exactly one shortcut for the icon update.");
            var entry=matches[0];
            var icons=entry.Children.Where(n=>string.Equals(n.Key,"icon",StringComparison.OrdinalIgnoreCase)).ToList();
            if(icons.Count>1 || (icons.Count==1 && icons[0].Type!=1)) throw new InvalidDataException("Invalid icon field.");
            int begin=icons.Count==1 ? icons[0].Start : entry.End-1;
            int end=icons.Count==1 ? icons[0].End : begin;
            using(var s=new MemoryStream()) using(var w=new BinaryWriter(s)) {
                w.Write(source,0,begin); Str(w,icons.Count==1 ? icons[0].Key : "icon",iconPath); w.Write(source,end,source.Length-end);
                var result=s.ToArray();
                var check=new SteamShortcuts(result);
                if(check.Items.Count!=Items.Count || check.Items.Single(i=>i.AppId==appId).Icon!=iconPath) throw new InvalidDataException("Icon update validation failed.");
                return result;
            }
        }
        public byte[] RepairLaunch(uint appId, string managedId, ShortcutDraft draft) {
            var matches=entries.Where(e=>Number(e,"appid")==appId).ToList();
            if(matches.Count!=1 || string.IsNullOrEmpty(managedId) || !managedId.StartsWith("steamnite:") || Text(matches[0],"DevkitGameID")!=managedId)
                throw new InvalidDataException("Repair requires one matching SteamNite-managed shortcut.");
            var entry=matches[0];
            var replacements=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase) {
                {"exe",draft.Exe}, {"StartDir",draft.StartDir}, {"LaunchOptions",draft.LaunchOptions}
            };
            foreach(var key in replacements.Keys) {
                var fields=entry.Children.Where(n=>string.Equals(n.Key,key,StringComparison.OrdinalIgnoreCase)).ToList();
                if(fields.Count>1 || (fields.Count==1 && fields[0].Type!=1)) throw new InvalidDataException("Invalid launch field: "+key);
            }
            using(var stream=new MemoryStream()) using(var writer=new BinaryWriter(stream)) {
                writer.Write(source,0,entry.Start);
                int properties=entry.Start+2+Utf8.GetByteCount(entry.Key);
                writer.Write(source,entry.Start,properties-entry.Start);
                foreach(var field in entry.Children) {
                    if(replacements.ContainsKey(field.Key)) { Str(writer,field.Key,replacements[field.Key]); replacements.Remove(field.Key); }
                    else writer.Write(source,field.Start,field.End-field.Start);
                }
                foreach(var pair in replacements) Str(writer,pair.Key,pair.Value);
                writer.Write(source,entry.End-1,source.Length-entry.End+1);
                var result=stream.ToArray();var check=new SteamShortcuts(result);
                var updated=check.Items.Single(i=>i.AppId==appId);
                if(check.Items.Count!=Items.Count || updated.Exe!=draft.Exe || updated.StartDir!=draft.StartDir || updated.LaunchOptions!=draft.LaunchOptions)
                    throw new InvalidDataException("Repair validation failed.");
                return result;
            }
        }
        public byte[] Append(ShortcutDraft[] drafts) {
            int next = Items.Count==0 ? 0 : Items.Max(i => int.Parse(i.Index))+1;
            var appIds = new HashSet<uint>(Items.Select(i=>i.AppId));
            using(var stream=new MemoryStream()) using(var w=new BinaryWriter(stream)) {
                w.Write(source,0,insertOffset);
                foreach(var d in drafts) {
                    if(d.AppId != AppId(d.Exe,d.Title) || !appIds.Add(d.AppId)) throw new InvalidDataException("Shortcut app ID collision or invalid ID.");
                    w.Write((byte)0); CString(w,(next++).ToString(System.Globalization.CultureInfo.InvariantCulture));
                    Int(w,"appid",d.AppId); Str(w,"AppName",d.Title); Str(w,"Exe",d.Exe); Str(w,"StartDir",d.StartDir);
                    Str(w,"icon",""); Str(w,"ShortcutPath",""); Str(w,"LaunchOptions",d.LaunchOptions);
                    Int(w,"IsHidden",0); Int(w,"AllowDesktopConfig",1); Int(w,"AllowOverlay",1); Int(w,"OpenVR",0);
                    Int(w,"Devkit",0); Str(w,"DevkitGameID",d.ManagedId); Int(w,"DevkitOverrideAppID",0); Int(w,"LastPlayTime",0);
                    Str(w,"FlatpakAppID",""); w.Write((byte)0); CString(w,"tags"); Str(w,"0","SteamNite"); w.Write((byte)8); w.Write((byte)8);
                }
                w.Write(source,insertOffset,source.Length-insertOffset);
                var result=stream.ToArray();
                var check=new SteamShortcuts(result);
                if(check.Items.Count!=Items.Count+drafts.Length) throw new InvalidDataException("Shortcut validation failed.");
                return result;
            }
        }
        public byte[] RemoveManaged(uint[] appIds) {
            return RemoveEntries(appIds,true);
        }
        // Only the explicit, confirmed shortcut-removal workflow uses this.
        // Automatic uninstall cleanup must continue to call RemoveManaged.
        public byte[] RemoveReviewed(uint[] appIds, bool allowManual) {
            return RemoveEntries(appIds,!allowManual);
        }
        byte[] RemoveEntries(uint[] appIds, bool managedOnly) {
            var selected=new HashSet<uint>(appIds);
            if(selected.Count!=appIds.Length) throw new InvalidDataException("Duplicate removal selection.");
            if(selected.Count==0) return (byte[])source.Clone();
            foreach(uint id in selected) {
                var matches=Items.Where(i=>i.AppId==id).ToList();
                if(matches.Count!=1 || (managedOnly && !System.Text.RegularExpressions.Regex.IsMatch(matches[0].ManagedId ?? "",@"^steamnite:(xbox|epic|amazon|gog|ubisoft|ea):.+$")))
                    throw new InvalidDataException("Removal is limited to uniquely identified SteamNite shortcuts.");
            }
            using(var stream=new MemoryStream()) using(var writer=new BinaryWriter(stream)) {
                int headerEnd=entries.Count==0 ? insertOffset : entries[0].Start;
                writer.Write(source,0,headerEnd);
                int index=0;
                foreach(var entry in entries) {
                    if(selected.Contains(Number(entry,"appid"))) continue;
                    // Reindex container keys for Steam; preserve every property byte of survivors.
                    writer.Write((byte)0); CString(writer,(index++).ToString(System.Globalization.CultureInfo.InvariantCulture));
                    int properties=entry.Start+2+Utf8.GetByteCount(entry.Key);
                    writer.Write(source,properties,entry.End-properties);
                }
                writer.Write(source,insertOffset,source.Length-insertOffset);
                var result=stream.ToArray();var check=new SteamShortcuts(result);
                if(check.Items.Count!=Items.Count-selected.Count || check.Items.Any(i=>selected.Contains(i.AppId))) throw new InvalidDataException("Removal validation failed.");
                return result;
            }
        }
    }
}
