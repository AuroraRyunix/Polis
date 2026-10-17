// The station's page: LiveView and nothing else. Everything the page does,
// the server does; this only opens the line to it, and asks before a
// button with data-confirm (Remove) does anything.
(function () {
  window.addEventListener(
    "click",
    (e) => {
      const el = e.target.closest && e.target.closest("[data-confirm]")
      if (el && !window.confirm(el.getAttribute("data-confirm"))) {
        e.preventDefault()
        e.stopImmediatePropagation()
      }
    },
    true
  )

  window.addEventListener("DOMContentLoaded", () => {
    const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content")
    const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
      params: { _csrf_token: csrf },
    })
    liveSocket.connect()
    window.liveSocket = liveSocket
  })
})()
