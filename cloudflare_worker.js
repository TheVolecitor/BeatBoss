/**
 * BeatBoss Dynamic Config & Update Worker
 * 
 * This Cloudflare Worker provides the current API Base URL 
 * and checks for application updates.
 */

export default {
  async fetch(request, env, ctx) {
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,HEAD,POST,OPTIONS",
      "Access-Control-Max-Age": "86400",
    };

    // Configuration
    const config = {
      // The current functional API base URL
      baseUrl: "https://beta.dabmusic.xyz/api",
      
      // Update information
      latestVersion: "1.8.0",
      updateAvailable: true, // Set to true to trigger in-app notification
      updateUrl: "https://github.com/BeatBoss/BeatBoss-App/releases/latest",
      releaseNotes: "Performance optimizations and dynamic configuration support."
    };

    return new Response(JSON.stringify(config), {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  },
};
