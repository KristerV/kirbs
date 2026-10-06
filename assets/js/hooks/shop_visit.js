// Tells the server once per browser session that the shop was entered ("shop_viewed" funnel
// step), no matter how many times the index LiveView is mounted by live navigation.
// Usage: <div id="shop-visit" phx-hook="ShopVisit" phx-update="ignore"></div>
export const ShopVisit = {
  mounted() {
    let seen = false
    try {
      seen = sessionStorage.getItem("kirbs_shop_visit") === "1"
      if (!seen) sessionStorage.setItem("kirbs_shop_visit", "1")
    } catch (_e) {
      // storage blocked: fall through and count the visit
    }
    if (!seen) this.pushEvent("shop_visit", {})
  },
}
