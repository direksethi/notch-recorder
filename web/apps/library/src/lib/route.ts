import { useEffect, useState } from "react"

export type Route =
  | { readonly view: "recordings" }
  | { readonly view: "unsaved" }
  | { readonly view: "transcripts"; readonly query?: string }
  | { readonly view: "recording"; readonly id: string; readonly at?: number }
  | { readonly view: "settings" }
  | { readonly view: "onboarding" }

export const parseRoute = (hash: string): Route => {
  const [path = "", qs = ""] = hash.replace(/^#/, "").split("?")
  const params = new URLSearchParams(qs)
  const parts = path.split("/").filter(Boolean)
  switch (parts[0]) {
    case "unsaved":
      return { view: "unsaved" }
    case "transcripts": {
      const q = params.get("q")
      return q ? { view: "transcripts", query: q } : { view: "transcripts" }
    }
    case "recording": {
      if (!parts[1]) return { view: "recordings" }
      const at = Number(params.get("t"))
      return Number.isFinite(at) && params.has("t")
        ? { view: "recording", id: decodeURIComponent(parts[1]), at }
        : { view: "recording", id: decodeURIComponent(parts[1]) }
    }
    case "settings":
      return { view: "settings" }
    case "onboarding":
      return { view: "onboarding" }
    default:
      return { view: "recordings" }
  }
}

export const href = (route: Route): string => {
  switch (route.view) {
    case "recording":
      return `#/recording/${encodeURIComponent(route.id)}${route.at === undefined ? "" : `?t=${Math.round(route.at)}`}`
    case "transcripts":
      return route.query ? `#/transcripts?q=${encodeURIComponent(route.query)}` : "#/transcripts"
    default:
      return `#/${route.view}`
  }
}

export const go = (route: Route) => {
  window.location.hash = href(route)
}

export const useRoute = (): Route => {
  const [route, setRoute] = useState(() => parseRoute(window.location.hash))
  useEffect(() => {
    const on = () => setRoute(parseRoute(window.location.hash))
    window.addEventListener("hashchange", on)
    return () => window.removeEventListener("hashchange", on)
  }, [])
  return route
}
