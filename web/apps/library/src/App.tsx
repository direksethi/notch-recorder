import { Sidebar } from "./components/Sidebar.tsx"
import { useRoute } from "./lib/route.ts"
import { DetailView } from "./views/DetailView.tsx"
import { OnboardingView } from "./views/OnboardingView.tsx"
import { RecordingsView } from "./views/RecordingsView.tsx"
import { SettingsView } from "./views/SettingsView.tsx"
import { TranscriptsView } from "./views/TranscriptsView.tsx"

export const App = () => {
  const route = useRoute()
  if (route.view === "onboarding") {
    return (
      <div className="h-full bg-canvas">
        <OnboardingView />
      </div>
    )
  }
  return (
    <div className="flex h-full bg-canvas">
      <Sidebar route={route} />
      <main className="min-w-0 flex-1">
        {route.view === "recordings" && <RecordingsView />}
        {route.view === "unsaved" && <RecordingsView unsavedOnly />}
        {route.view === "transcripts" && <TranscriptsView {...(route.query ? { initialQuery: route.query } : {})} />}
        {route.view === "recording" && <DetailView key={route.id} id={route.id} {...(route.at !== undefined ? { at: route.at } : {})} />}
        {route.view === "settings" && <SettingsView />}
      </main>
    </div>
  )
}
