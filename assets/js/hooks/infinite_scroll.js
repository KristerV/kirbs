// Fires the element's phx-click event automatically when it scrolls near the viewport, so a
// "load more" button turns into infinite scroll. The button still works as a manual fallback.
// Usage: <button id="load-more" phx-hook="InfiniteScroll" phx-click="load_more">…</button>
export const InfiniteScroll = {
  mounted() {
    this.loading = false
    this.visible = false
    this.observer = new IntersectionObserver(
      (entries) => {
        this.visible = entries.some((e) => e.isIntersecting)
        if (this.visible) this.load()
      },
      {rootMargin: "600px 0px"},
    )
    this.observer.observe(this.el)
  },

  load() {
    if (this.loading) return
    this.loading = true
    this.pushEvent(this.el.getAttribute("phx-click"), {})
      .catch(() => {})
      .finally(() => {
        this.loading = false
        // still near the bottom (short page / fast scroll): keep loading
        if (this.visible && this.el.isConnected) requestAnimationFrame(() => this.load())
      })
  },

  destroyed() {
    this.observer.disconnect()
  },
}
