// Removes the HTML loading screen (index.html) once Flutter paints its first
// frame. A separate file so the Content-Security-Policy needs no inline script.
window.addEventListener('flutter-first-frame', function () {
  var loading = document.getElementById('axon-loading');
  if (!loading) return;
  loading.style.opacity = '0';
  setTimeout(function () { loading.remove(); }, 300);
});
