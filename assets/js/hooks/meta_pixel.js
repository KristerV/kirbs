// Meta (Facebook) pixel integration. Inert unless a layout renders
//   <div id="meta-pixel" phx-hook="MetaPixel" data-pixel-id={@meta_pixel_id}></div>
// (only when @meta_pixel_id is set). The server fires events through KirbsWeb.Track, which
// does push_event(socket, "meta_pixel", %{event: "Purchase", data: %{...}}).
function loadPixel(pixelId) {
  if (window.fbq) return
  const fbq = (window.fbq = function () {
    fbq.callMethod ? fbq.callMethod.apply(fbq, arguments) : fbq.queue.push(arguments)
  })
  if (!window._fbq) window._fbq = fbq
  fbq.push = fbq
  fbq.loaded = true
  fbq.version = "2.0"
  fbq.queue = []
  const s = document.createElement("script")
  s.async = true
  s.src = "https://connect.facebook.net/en_US/fbevents.js"
  document.head.appendChild(s)
  window.fbq("init", pixelId)
}

export const MetaPixel = {
  mounted() {
    const pixelId = this.el.dataset.pixelId
    if (!pixelId) return
    loadPixel(pixelId)
    window.fbq("track", "PageView")
    this.handleEvent("meta_pixel", ({event, data}) => {
      window.fbq("track", event, data || {})
    })
  },
}
