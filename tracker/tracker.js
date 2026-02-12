(function() {
  "use strict";

  var endpoint = "ANALYTICS_ENDPOINT_URL/track";

  // Respect Do Not Track
  if (navigator.doNotTrack === "1") return;

  // Don't track prerendered pages
  if (document.visibilityState === "prerender") return;

  var data = JSON.stringify({
    url: window.location.pathname,
    referrer: document.referrer || null
  });

  // sendBeacon avoids CORS preflight (sends as text/plain) and survives page unload
  if (navigator.sendBeacon) {
    navigator.sendBeacon(endpoint, data);
  } else {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", endpoint, true);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.send(data);
  }
})();
