// Counts down to data-deadline (ISO 8601) and renders m:ss into the element.
// Usage: <span id="countdown" phx-hook="Countdown" phx-update="ignore" data-deadline={iso}>
// The server enforces the deadline; this is display only.
export const Countdown = {
  mounted() {
    this.deadline = Date.parse(this.el.dataset.deadline)
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  },
  destroyed() {
    clearInterval(this.timer)
  },
  tick() {
    const left = Math.max(0, Math.round((this.deadline - Date.now()) / 1000))
    const minutes = Math.floor(left / 60)
    const seconds = String(left % 60).padStart(2, "0")
    this.el.textContent = `${minutes}:${seconds}`
    if (left === 0) clearInterval(this.timer)
  },
}
