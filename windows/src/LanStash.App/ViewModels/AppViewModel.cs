using System.Collections.ObjectModel;
using System.Text.Json;
using LanStash.App.Localization;
using LanStash.Domain;
using LanStash.Infrastructure;

namespace LanStash.App.ViewModels;

public sealed class AppViewModel : ObservableObject
{
    private readonly HttpClient _http = new(new HttpClientHandler
    {
        AllowAutoRedirect = false,
    })
    {
        Timeout = TimeSpan.FromSeconds(45),
    };
    private readonly ISecureSessionStore _sessionStore = new CredentialSessionStore();
    private readonly ISecurePasswordStore _passwordStore = new CredentialPasswordStore();
    private readonly IDsmApiClient _api;
    private readonly DsmConnectionResolver _connectionResolver;
    private readonly string _profilesPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "LanStash",
        "profiles.json");
    private bool _isBusy;
    private string? _errorMessage;
    private string? _connectionStatus;
    private string _displayName = LocalizationService.Current.Get("DefaultNasName");
    private string _host = string.Empty;
    private string _port = string.Empty;
    private string _username = string.Empty;
    private string _password = string.Empty;
    private string _otp = string.Empty;
    private bool _rememberPassword;
    private bool _autoLogin;
    private bool _isInitialized;

    public AppViewModel()
    {
        _api = new DsmApiClient(_http);
        _connectionResolver = new DsmConnectionResolver(
            _api,
            new DsmQuickConnectResolver(_http));
    }

    public event EventHandler<bool>? ConnectionChanged;
    public event EventHandler<string>? PasswordLoaded;

    public ObservableCollection<NasProfile> Profiles { get; } = [];
    public ObservableCollection<AppModule> AvailableModules { get; } = [];

    public NasProfile? ActiveProfile { get; private set; }
    private NasProfile? ActiveConnectionProfile { get; set; }
    public DsmSession? Session { get; private set; }
    public IDsmRepository? Repository { get; private set; }

    public string DisplayName
    {
        get => _displayName;
        set => SetProperty(ref _displayName, value);
    }

    public string Host
    {
        get => _host;
        set => SetProperty(ref _host, value);
    }

    public string Port
    {
        get => _port;
        set => SetProperty(ref _port, value);
    }

    public string Username
    {
        get => _username;
        set => SetProperty(ref _username, value);
    }

    public string Password
    {
        get => _password;
        set => SetProperty(ref _password, value);
    }

    public string Otp
    {
        get => _otp;
        set => SetProperty(ref _otp, value);
    }

    public bool RememberPassword
    {
        get => _rememberPassword;
        set
        {
            if (SetProperty(ref _rememberPassword, value) && !value)
            {
                AutoLogin = false;
            }
        }
    }

    public bool AutoLogin
    {
        get => _autoLogin;
        set
        {
            if (SetProperty(ref _autoLogin, value) && value)
            {
                RememberPassword = true;
            }
        }
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set => SetProperty(ref _isBusy, value);
    }

    public string? ErrorMessage
    {
        get => _errorMessage;
        private set => SetProperty(ref _errorMessage, value);
    }

    public string? ConnectionStatus
    {
        get => _connectionStatus;
        private set => SetProperty(ref _connectionStatus, value);
    }

    public async Task InitializeAsync()
    {
        if (_isInitialized)
        {
            return;
        }
        _isInitialized = true;
        await LoadProfilesAsync().ConfigureAwait(true);
        var profile = Profiles.LastOrDefault();
        if (profile is null)
        {
            return;
        }
        await SelectProfileAsync(profile).ConfigureAwait(true);
        if (profile.AutoLogin && !string.IsNullOrEmpty(Password))
        {
            await RestoreAsync(profile, fallbackToPassword: true).ConfigureAwait(true);
        }
    }

    public async Task SelectProfileAsync(NasProfile profile)
    {
        DisplayName = profile.DisplayName;
        Host = profile.Host;
        Port = profile.Port?.ToString() ?? string.Empty;
        Username = profile.Username;
        Password = await _passwordStore.LoadAsync(profile.Id).ConfigureAwait(true) ?? string.Empty;
        RememberPassword = !string.IsNullOrEmpty(Password);
        AutoLogin = profile.AutoLogin && RememberPassword;
        PasswordLoaded?.Invoke(this, Password);
        Otp = string.Empty;
        ErrorMessage = null;
        ConnectionStatus = null;
    }

    public void NewProfile()
    {
        DisplayName = LocalizationService.Current.Get("DefaultNasName");
        Host = string.Empty;
        Port = string.Empty;
        Username = string.Empty;
        Password = string.Empty;
        RememberPassword = false;
        AutoLogin = false;
        PasswordLoaded?.Invoke(this, string.Empty);
        Otp = string.Empty;
        ErrorMessage = null;
        ConnectionStatus = null;
    }

    public async Task ConnectAsync()
    {
        if (IsBusy)
        {
            return;
        }
        IsBusy = true;
        ErrorMessage = null;
        var localization = LocalizationService.Current;
        ConnectionStatus = localization.Get("StatusCheckingNas");
        try
        {
            var profile = new NasProfile(
                Profiles.FirstOrDefault(item =>
                    string.Equals(item.Host, Host, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(item.Username, Username, StringComparison.Ordinal))?.Id
                    ?? Guid.NewGuid(),
                string.IsNullOrWhiteSpace(DisplayName) ? "NAS" : DisplayName.Trim(),
                Host.Trim(),
                int.TryParse(Port, out var port) ? port : null,
                Username.Trim(),
                RememberPassword,
                AutoLogin && RememberPassword);
            var connection = await _connectionResolver.DiscoverAsync(
                profile,
                status => ConnectionStatus = localization.ResolveUserText(status)).ConfigureAwait(true);
            ConnectionStatus = localization.Get("StatusNasFoundSigningIn");
            var session = await _api.LoginAsync(
                connection.Profile,
                Password,
                string.IsNullOrWhiteSpace(Otp) ? null : Otp).ConfigureAwait(true);
            if (RememberPassword)
            {
                await _sessionStore.SaveAsync(session).ConfigureAwait(true);
                await _passwordStore.SaveAsync(profile.Id, Password).ConfigureAwait(true);
            }
            else
            {
                await _sessionStore.RemoveAsync(profile.Id).ConfigureAwait(true);
                await _passwordStore.RemoveAsync(profile.Id).ConfigureAwait(true);
            }
            CompleteConnection(profile, connection.Profile, session, connection.Capabilities);
            await SaveProfileAsync(profile).ConfigureAwait(true);
            if (!RememberPassword)
            {
                Password = string.Empty;
                PasswordLoaded?.Invoke(this, string.Empty);
            }
        }
        catch (DsmException error)
        {
            ErrorMessage = localization.ErrorMessage(error);
        }
        catch
        {
            ErrorMessage = localization.Get("ErrorConnectGeneric");
        }
        finally
        {
            IsBusy = false;
            ConnectionStatus = null;
        }
    }

    public async Task RestoreAsync(NasProfile profile, bool fallbackToPassword = false)
    {
        if (IsBusy)
        {
            return;
        }
        IsBusy = true;
        ErrorMessage = null;
        var localization = LocalizationService.Current;
        ConnectionStatus = localization.Get("StatusRestoringLogin");
        var shouldFallbackToPassword = false;
        try
        {
            var session = await _sessionStore.LoadAsync(profile.Id).ConfigureAwait(true);
            if (session is null)
            {
                throw new DsmException(
                    UserText.Key("ErrorSavedLoginExpired"),
                    UserText.Key("RecoverySignInAgain"));
            }
            var connection = await _connectionResolver.DiscoverAsync(
                profile,
                status => ConnectionStatus = localization.ResolveUserText(status)).ConfigureAwait(true);
            var repository = new DsmRepository(
                connection.Profile,
                session,
                _api,
                connection.Capabilities);
            _ = await repository.ListFilesAsync(string.Empty).ConfigureAwait(true);
            CompleteConnection(profile, connection.Profile, session, connection.Capabilities);
        }
        catch (DsmException error)
        {
            await _sessionStore.RemoveAsync(profile.Id).ConfigureAwait(true);
            await SelectProfileAsync(profile).ConfigureAwait(true);
            shouldFallbackToPassword =
                fallbackToPassword &&
                profile.AutoLogin &&
                !string.IsNullOrEmpty(Password);
            if (!shouldFallbackToPassword)
            {
                ErrorMessage = string.IsNullOrEmpty(Password)
                    ? $"{localization.ResolveUserText(error.Message)} {localization.Get("RecoveryEnterPasswordAgain")}"
                    : $"{localization.ResolveUserText(error.Message)} {localization.Get("RecoveryPasswordReady")}";
            }
        }
        finally
        {
            IsBusy = false;
            ConnectionStatus = null;
        }
        if (shouldFallbackToPassword)
        {
            await ConnectAsync().ConfigureAwait(true);
        }
    }

    public async Task RemoveProfileAsync(NasProfile profile)
    {
        Profiles.Remove(profile);
        await _sessionStore.RemoveAsync(profile.Id).ConfigureAwait(true);
        await _passwordStore.RemoveAsync(profile.Id).ConfigureAwait(true);
        await PersistProfilesAsync().ConfigureAwait(true);
    }

    public async Task LogoutAsync()
    {
        var profile = ActiveProfile;
        if (profile is not null)
        {
            if (Session is not null)
            {
                try
                {
                    await _api.LogoutAsync(
                        ActiveConnectionProfile ?? profile,
                        Session).ConfigureAwait(true);
                }
                catch
                {
                    // NAS 暂时不可达时也必须完成本机退出。
                }
            }
            await _sessionStore.RemoveAsync(profile.Id).ConfigureAwait(true);
            var signedOutProfile = profile with { AutoLogin = false };
            var index = Profiles.IndexOf(profile);
            if (index >= 0)
            {
                Profiles[index] = signedOutProfile;
                await PersistProfilesAsync().ConfigureAwait(true);
            }
            AutoLogin = false;
        }
        ActiveProfile = null;
        ActiveConnectionProfile = null;
        Session = null;
        Repository = null;
        AvailableModules.Clear();
        ConnectionChanged?.Invoke(this, false);
    }

    private void CompleteConnection(
        NasProfile profile,
        NasProfile connectionProfile,
        DsmSession session,
        IReadOnlyDictionary<string, ApiCapability> capabilities)
    {
        ActiveProfile = profile;
        ActiveConnectionProfile = connectionProfile;
        Session = session;
        Repository = new DsmRepository(connectionProfile, session, _api, capabilities);
        AvailableModules.Clear();
        foreach (var module in Repository.AvailableModules)
        {
            AvailableModules.Add(module);
        }
        ConnectionChanged?.Invoke(this, true);
    }

    private async Task LoadProfilesAsync()
    {
        try
        {
            if (!File.Exists(_profilesPath))
            {
                return;
            }
            var content = await File.ReadAllTextAsync(_profilesPath);
            var profiles = JsonSerializer.Deserialize<List<NasProfile>>(content) ?? [];
            foreach (var profile in profiles)
            {
                Profiles.Add(profile);
            }
        }
        catch
        {
            ErrorMessage = LocalizationService.Current.Get("ErrorLoadProfiles");
        }
    }

    private async Task SaveProfileAsync(NasProfile profile)
    {
        var existing = Profiles.FirstOrDefault(item => item.Id == profile.Id);
        if (existing is not null)
        {
            Profiles.Remove(existing);
        }
        Profiles.Add(profile);
        await PersistProfilesAsync().ConfigureAwait(true);
    }

    private async Task PersistProfilesAsync()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_profilesPath)!);
        var temporaryPath = $"{_profilesPath}.tmp";
        await File.WriteAllTextAsync(
            temporaryPath,
            JsonSerializer.Serialize(Profiles.ToArray()));
        File.Move(temporaryPath, _profilesPath, overwrite: true);
    }
}
