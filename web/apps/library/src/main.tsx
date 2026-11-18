import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "./App.tsx"
import { RuntimeProvider, ToastProvider } from "./hooks/effect.tsx"
import { LibraryProvider } from "./library.tsx"
import { installTitlebar } from "./lib/titlebar.ts"
import { runtime } from "./runtime.ts"
import "./styles.css"

installTitlebar()

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <RuntimeProvider runtime={runtime}>
      <ToastProvider>
        <LibraryProvider>
          <App />
        </LibraryProvider>
      </ToastProvider>
    </RuntimeProvider>
  </StrictMode>,
)
