using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;

namespace SteamNite {
    public static class ArtworkHttp {
        public static bool AllowedImageUrl(string value) {
            Uri uri;
            return Uri.TryCreate(value,UriKind.Absolute,out uri) && uri.Scheme=="https" && uri.IsDefaultPort &&
                string.IsNullOrEmpty(uri.UserInfo) && (uri.Host=="steamgriddb.com" || uri.Host.EndsWith(".steamgriddb.com",StringComparison.OrdinalIgnoreCase));
        }
        static HttpClient Client() {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var c=new HttpClient(new HttpClientHandler { AllowAutoRedirect=false });
            c.Timeout=TimeSpan.FromSeconds(30); c.DefaultRequestHeaders.UserAgent.ParseAdd("SteamNite/0.3"); return c;
        }
        static void Check(HttpResponseMessage response) {
            if(response.StatusCode==HttpStatusCode.Unauthorized || response.StatusCode==HttpStatusCode.Forbidden)
                throw new InvalidOperationException("SteamGridDB rejected the request. Check your API key and account access.");
            if((int)response.StatusCode==429) throw new InvalidOperationException("SteamGridDB rate limit reached. Please wait before trying again.");
            if(!response.IsSuccessStatusCode) throw new InvalidOperationException("SteamGridDB request failed (HTTP "+(int)response.StatusCode+").");
        }
        static byte[] Get(string url,string key,int maximum) {
            using(var c=Client()) using(var request=new HttpRequestMessage(HttpMethod.Get,url)) using(var cancel=new CancellationTokenSource(TimeSpan.FromSeconds(30))) {
                if(key!=null) request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",key);
                using(var response=c.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,cancel.Token).GetAwaiter().GetResult()) {
                    Check(response);
                    if(response.Content.Headers.ContentLength>maximum) throw new InvalidOperationException("Response exceeds the download size limit.");
                    using(var input=response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()) using(var output=new MemoryStream()) {
                        byte[] buffer=new byte[65536]; int count;
                        while((count=input.ReadAsync(buffer,0,buffer.Length,cancel.Token).GetAwaiter().GetResult())!=0) {
                            if(output.Length+count>maximum) throw new InvalidOperationException("Response exceeds the download size limit.");
                            output.Write(buffer,0,count);
                        }
                        return output.ToArray();
                    }
                }
            }
        }
        public static string Api(string relativePath,string key) {
            if(string.IsNullOrWhiteSpace(key) || key.Length>256 || key.IndexOfAny(new char[]{'\r','\n'})>=0)
                throw new InvalidOperationException("Enter a valid SteamGridDB API key in the masked field.");
            if(!relativePath.StartsWith("/") || relativePath.StartsWith("//") || relativePath.Contains("..") || relativePath.Contains("\\"))
                throw new InvalidOperationException("Invalid API request path.");
            return System.Text.Encoding.UTF8.GetString(Get("https://www.steamgriddb.com/api/v2"+relativePath,key,4*1024*1024));
        }
        public static void Download(string url,string destination) {
            if(!AllowedImageUrl(url)) throw new InvalidOperationException("Artwork must use an HTTPS SteamGridDB image URL.");
            File.WriteAllBytes(destination,Get(url,null,20*1024*1024));
        }
    }
}
