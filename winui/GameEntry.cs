using Microsoft.UI;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
namespace SteamNite.WinUI;
public sealed class GameEntry : System.ComponentModel.INotifyPropertyChanged
{
    public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;
    bool selected;
    BitmapImage? cover;
    [System.Text.Json.Serialization.JsonIgnore] public bool IsSelected { get => selected; set { if (selected == value) return; selected = value; PropertyChanged?.Invoke(this, new(nameof(IsSelected))); } }
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Platform { get; set; } = "";
    public string InstallState { get; set; } = "";
    public string SteamSyncStatus { get; set; } = "";
    public string ArtworkStatus { get; set; } = "";
    public string[] MissingArtwork { get; set; } = [];
    public string InstallPath { get; set; } = "";
    public string Method { get; set; } = "";
    public string Target { get; set; } = "";
    public string AttentionDetail { get; set; } = "";
    public string SteamSyncDetail { get; set; } = "";
    public string ArtworkDetail { get; set; } = "";
    public string CoverPath { get; set; } = "";
    public bool NeedsAttention { get; set; }
    public bool Ignored { get; set; }
    public bool CanRemove { get; set; }
    public bool CanRemoveExplicitly { get; set; }
    public string NativeGameId { get; set; } = "";
    public string Status { get; set; } = "";
    public override string ToString() => Title;
    [System.Text.Json.Serialization.JsonIgnore] public BitmapImage? Cover { get => cover; set { cover = value; PropertyChanged?.Invoke(this, new(nameof(Cover))); } }
    [System.Text.Json.Serialization.JsonIgnore] public SolidColorBrush StatusBrush => Brush(LibraryPresentation.SteamTone(SteamSyncStatus, Ignored));
    [System.Text.Json.Serialization.JsonIgnore] public SolidColorBrush InstallBrush => Brush(LibraryPresentation.InstallationTone(InstallState, Ignored));
    [System.Text.Json.Serialization.JsonIgnore] public SolidColorBrush ArtworkBrush => Brush(LibraryPresentation.ArtworkTone(ArtworkStatus, Ignored));
    static SolidColorBrush Brush(string key) => (SolidColorBrush)Microsoft.UI.Xaml.Application.Current.Resources[key];
}
