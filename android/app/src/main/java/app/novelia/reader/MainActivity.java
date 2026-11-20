package app.novelia.reader;

import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
import android.webkit.WebResourceRequest;
import android.webkit.JavascriptInterface;
import android.content.Intent;
import android.net.Uri;
import android.media.AudioManager;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.media.MediaMetadata;
import android.content.Context;

public class MainActivity extends Activity {
    private WebView webView;
    private MediaSession mediaSession;
    private static MainActivity instance;
    private String currentMediaTitle = "Novelia";
    private String currentMediaAuthor = "Novelia";
    private final AudioManager.OnAudioFocusChangeListener audioFocusListener = this::handleAudioFocusChange;
    private boolean hasAudioFocus = false;
    private boolean resumeAfterFocusGain = false;
    private boolean pauseWasCausedByFocus = false;
    private static final String HOME = "https://johntoulassi31-rgb.github.io/novelia/";

    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        instance = this;
        mediaSession = new MediaSession(this, "NoveliaAudio");
        mediaSession.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS | MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS);
        mediaSession.setCallback(new MediaSession.Callback() {
            @Override public void onPlay() { sendPlayerCommand("play"); }
            @Override public void onPause() { sendPlayerCommand("pause"); }
            @Override public void onSkipToNext() { sendPlayerCommand("next"); }
            @Override public void onSkipToPrevious() { sendPlayerCommand("previous"); }
            @Override public void onStop() { sendPlayerCommand("pause"); }
        });
        webView = new WebView(this);
        setContentView(webView);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        webView.addJavascriptInterface(new NoveliaMediaBridge(), "NoveliaNativeMedia");
        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String host = uri.getHost();
                if (host != null && (host.equals("johntoulassi31-rgb.github.io") || host.equals("czwaokqpqgrghxeeyguq.supabase.co"))) return false;
                startActivity(new Intent(Intent.ACTION_VIEW, uri));
                return true;
            }
        });
        if (savedInstanceState == null) webView.loadUrl(HOME);
        else webView.restoreState(savedInstanceState);
    }

    private void handleAudioFocusChange(int focusChange) {
        if (focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
                || focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) {
            resumeAfterFocusGain = true;
            pauseWasCausedByFocus = true;
            sendPlayerCommand("pause");
        } else if (focusChange == AudioManager.AUDIOFOCUS_LOSS) {
            resumeAfterFocusGain = false;
            pauseWasCausedByFocus = false;
            hasAudioFocus = false;
            sendPlayerCommand("pause");
        } else if (focusChange == AudioManager.AUDIOFOCUS_GAIN && resumeAfterFocusGain) {
            resumeAfterFocusGain = false;
            pauseWasCausedByFocus = false;
            sendPlayerCommand("play");
        }
    }

    private boolean requestMediaAudioFocus() {
        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        int result = audioManager.requestAudioFocus(audioFocusListener,
            AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN);
        hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
        return hasAudioFocus;
    }

    private void abandonMediaAudioFocus() {
        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        audioManager.abandonAudioFocus(audioFocusListener);
        hasAudioFocus = false;
        resumeAfterFocusGain = false;
        pauseWasCausedByFocus = false;
    }

    private void sendPlayerCommand(String command) {
        runOnUiThread(() -> {
            if (webView != null) webView.evaluateJavascript(
                "window.NoveliaHandleNativeMediaAction && window.NoveliaHandleNativeMediaAction('" + command + "')", null);
        });
    }

    private void setNativePlayback(String title, String author, boolean playing) {
        if (playing && !hasAudioFocus && !requestMediaAudioFocus()) {
            sendPlayerCommand("pause");
            return;
        }
        currentMediaTitle = title == null ? "Novelia" : title;
        currentMediaAuthor = author == null ? "Novelia" : author;
        mediaSession.setMetadata(new MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title == null ? "Novelia" : title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, author == null ? "Novelia" : author)
            .putString(MediaMetadata.METADATA_KEY_ALBUM, "Novelia · Lecture audio")
            .build());
        long actions = PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE
            | PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS | PlaybackState.ACTION_STOP;
        mediaSession.setPlaybackState(new PlaybackState.Builder()
            .setActions(actions)
            .setState(playing ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_PAUSED, 0, 1f)
            .build());
        mediaSession.setActive(true);
        Intent service = new Intent(this, NoveliaPlaybackService.class);
        if (playing) {
            service.setAction(NoveliaPlaybackService.ACTION_START);
            service.putExtra(NoveliaPlaybackService.EXTRA_TITLE, title);
            service.putExtra(NoveliaPlaybackService.EXTRA_TOKEN, mediaSession.getSessionToken());
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(service); else startService(service);
        }
    }

    private final class NoveliaMediaBridge {
        @JavascriptInterface public void update(String title, String author) {
            runOnUiThread(() -> setNativePlayback(title, author, false));
        }
        @JavascriptInterface public void playing(String title, String author) {
            runOnUiThread(() -> setNativePlayback(title, author, true));
        }
        @JavascriptInterface public void paused() {
            runOnUiThread(() -> {
                setNativePlayback(currentMediaTitle, currentMediaAuthor, false);
                if (!pauseWasCausedByFocus) abandonMediaAudioFocus();
                Intent service = new Intent(MainActivity.this, NoveliaPlaybackService.class);
                service.setAction(NoveliaPlaybackService.ACTION_PAUSE);
                service.putExtra(NoveliaPlaybackService.EXTRA_TITLE, currentMediaTitle);
                service.putExtra(NoveliaPlaybackService.EXTRA_TOKEN, mediaSession.getSessionToken());
                startService(service);
            });
        }
        @JavascriptInterface public void stopped() {
            runOnUiThread(() -> {
                abandonMediaAudioFocus();
                mediaSession.setActive(false);
                stopService(new Intent(MainActivity.this, NoveliaPlaybackService.class));
            });
        }
    }

    public static void releaseNativeSession() {
        if (instance != null && instance.mediaSession != null) {
            instance.mediaSession.setActive(false);
            instance.mediaSession.release();
            instance.mediaSession = null;
        }
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if (webView != null) webView.saveState(outState);
    }

    @Override protected void onDestroy() {
        if (isFinishing()) {
            abandonMediaAudioFocus();
            stopService(new Intent(this, NoveliaPlaybackService.class));
            releaseNativeSession();
            instance = null;
        }
        super.onDestroy();
    }

    @Override public void onBackPressed() {
        if (webView != null && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }
}
