package app.novelia.reader;

import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.webkit.WebChromeClient;
import android.webkit.ValueCallback;
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
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import android.view.ViewGroup;

public class MainActivity extends Activity {
    private WebView webView;
    private ValueCallback<Uri[]> fileChooserCallback;
    private static final int FILE_CHOOSER_REQUEST = 1001;
    private View splashOverlay;
    private MediaSession mediaSession;
    private static MainActivity instance;
    private String currentMediaTitle = "Novelia";
    private String currentMediaAuthor = "Novelia";
    private final AudioManager.OnAudioFocusChangeListener audioFocusListener = this::handleAudioFocusChange;
    private boolean hasAudioFocus = false;
    private boolean resumeAfterFocusGain = false;
    private boolean pauseWasCausedByFocus = false;
    private static final String HOME = "https://johntoulassi31-rgb.github.io/novelia/";
    private static final long EXIT_BACK_INTERVAL_MS = 2000;
    private long lastBackPressedAt = 0;

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
        FrameLayout root = new FrameLayout(this);
        root.addView(webView, new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        splashOverlay = createSplashOverlay();
        root.addView(splashOverlay, new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(root);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        webView.addJavascriptInterface(new NoveliaMediaBridge(), "NoveliaNativeMedia");
        webView.addJavascriptInterface(new NoveliaUpdateBridge(), "NoveliaNativeApp");
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> filePathCallback,
                    FileChooserParams fileChooserParams) {
                if (MainActivity.this.fileChooserCallback != null) {
                    MainActivity.this.fileChooserCallback.onReceiveValue(null);
                }
                MainActivity.this.fileChooserCallback = filePathCallback;
                try {
                    Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);
                    intent.setType("image/*");
                    startActivityForResult(Intent.createChooser(intent, "Choisir une couverture"), FILE_CHOOSER_REQUEST);
                    return true;
                } catch (Exception error) {
                    MainActivity.this.fileChooserCallback = null;
                    filePathCallback.onReceiveValue(null);
                    return false;
                }
            }
        });
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView view, String url) {
                if (splashOverlay != null) splashOverlay.setVisibility(View.GONE);
                Uri pageUri = Uri.parse(url);
                if ("johntoulassi31-rgb.github.io".equals(pageUri.getHost())) {
                    view.evaluateJavascript("(function(){var s=document.createElement('script');s.src='https://johntoulassi31-rgb.github.io/novelia/update-check.js?v=1';s.async=true;document.head.appendChild(s);})();", null);
                }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String host = uri.getHost();
                if (host != null && (
                    host.equals("johntoulassi31-rgb.github.io")
                    || host.equals("czwaokqpqgrghxeeyguq.supabase.co")
                    || host.equals("cinetpay.com") || host.endsWith(".cinetpay.com")
                    || host.equals("cinetpay.co") || host.endsWith(".cinetpay.co")
                    || host.equals("cinetpay.net") || host.endsWith(".cinetpay.net")
                )) return false;
                startActivity(new Intent(Intent.ACTION_VIEW, uri));
                return true;
            }
        });
        if (savedInstanceState == null) webView.loadUrl(HOME);
        else webView.restoreState(savedInstanceState);
    }


    private View createSplashOverlay() {
        FrameLayout screen = new FrameLayout(this);
        GradientDrawable background = new GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            new int[] { Color.rgb(13, 7, 39), Color.rgb(35, 10, 77), Color.rgb(9, 5, 31) });
        screen.setBackground(background);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER);
        content.setPadding(dp(26), dp(24), dp(26), dp(24));
        FrameLayout.LayoutParams contentParams = new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER);
        screen.addView(content, contentParams);

        TextView brand = new TextView(this);
        brand.setText("Novelia");
        brand.setTextColor(Color.rgb(255, 207, 91));
        brand.setTextSize(58);
        brand.setTypeface(Typeface.SERIF, Typeface.ITALIC);
        brand.setGravity(Gravity.CENTER);
        brand.setShadowLayer(dp(14), 0, dp(2), Color.rgb(190, 112, 23));
        content.addView(brand, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView tagline = new TextView(this);
        tagline.setText("Lire sans limites");
        tagline.setTextColor(Color.rgb(239, 205, 143));
        tagline.setTextSize(15);
        tagline.setTypeface(Typeface.SERIF, Typeface.ITALIC);
        tagline.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams taglineParams = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        taglineParams.bottomMargin = dp(22);
        content.addView(tagline, taglineParams);

        View separator = new View(this);
        GradientDrawable line = new GradientDrawable();
        line.setColor(Color.rgb(197, 145, 59));
        line.setCornerRadius(dp(2));
        separator.setBackground(line);
        LinearLayout.LayoutParams lineParams = new LinearLayout.LayoutParams(dp(74), dp(1));
        lineParams.bottomMargin = dp(18);
        content.addView(separator, lineParams);

        TextView quote = new TextView(this);
        quote.setText("Lire c’est nous permettre de rêver\n"
            + "Grâce au roman, grâce aux BD, grâce à la poésie.\n"
            + "Lire c’est voyager à travers le temps\n"
            + "Voyager parmi tous les peuples,\n"
            + "Lire c’est avoir le monde entier à nos pieds,\n"
            + "Sans bouger !!!");
        quote.setTextColor(Color.rgb(247, 229, 199));
        quote.setTextSize(12);
        quote.setTypeface(Typeface.SERIF, Typeface.ITALIC);
        quote.setGravity(Gravity.CENTER);
        quote.setLineSpacing(dp(3), 1.0f);
        quote.setPadding(dp(8), dp(4), dp(8), dp(4));
        content.addView(quote, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return screen;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
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

    private final class NoveliaUpdateBridge {
        @JavascriptInterface public int getVersionCode() {
            try {
                return getPackageManager().getPackageInfo(getPackageName(), 0).versionCode;
            } catch (Exception error) {
                return 0;
            }
        }
        @JavascriptInterface public String getVersionName() {
            try {
                return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
            } catch (Exception error) {
                return "";
            }
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

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == FILE_CHOOSER_REQUEST) {
            if (fileChooserCallback != null) {
                Uri[] results = null;
                if (resultCode == Activity.RESULT_OK && data != null && data.getData() != null) {
                    results = new Uri[] { data.getData() };
                }
                fileChooserCallback.onReceiveValue(results);
                fileChooserCallback = null;
            }
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

    private boolean isHomePage() {
        if (webView == null || webView.getUrl() == null) return true;
        Uri current = Uri.parse(webView.getUrl());
        String path = current.getPath();
        return "johntoulassi31-rgb.github.io".equals(current.getHost())
            && (path == null || path.isEmpty() || "/".equals(path) || "/index.html".equals(path));
    }

    @Override public void onBackPressed() {
        // Respect the real navigation history inside Novelia.
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
            lastBackPressedAt = 0;
            return;
        }
        // At the application root, require two consecutive Back presses to exit.
        long now = System.currentTimeMillis();
        if (now - lastBackPressedAt < EXIT_BACK_INTERVAL_MS) {
            lastBackPressedAt = 0;
            finish();
            return;
        }
        lastBackPressedAt = now;
        Toast.makeText(this, "Appuyez encore sur Retour pour quitter Novelia", Toast.LENGTH_SHORT).show();
    }
}
