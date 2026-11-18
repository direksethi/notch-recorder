/** Splits a highlighted string (U+0001 ... U+0002 markers) into parts. */
export interface HighlightPart {
  readonly text: string
  readonly match: boolean
}

export const splitHighlight = (value: string): Array<HighlightPart> => {
  const parts: Array<HighlightPart> = []
  let rest = value
  while (rest.length > 0) {
    const start = rest.indexOf("\u0001")
    if (start === -1) {
      parts.push({ text: rest, match: false })
      break
    }
    if (start > 0) parts.push({ text: rest.slice(0, start), match: false })
    const end = rest.indexOf("\u0002", start)
    const stop = end === -1 ? rest.length : end
    parts.push({ text: rest.slice(start + 1, stop), match: true })
    rest = end === -1 ? "" : rest.slice(end + 1)
  }
  return parts
}

export const groupBy = <A, K extends string>(items: ReadonlyArray<A>, key: (a: A) => K): Map<K, Array<A>> => {
  const map = new Map<K, Array<A>>()
  for (const item of items) {
    const k = key(item)
    const list = map.get(k)
    if (list) list.push(item)
    else map.set(k, [item])
  }
  return map
}
