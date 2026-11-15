import type {
  LyricsLine,
  LyricsResult,
  TrackInfo
} from '../typings/lyrics/musixmatch.types.ts'
import type { HttpProxyConfig } from '../typings/utils.types.ts'
import { logger, makeRequest } from '../utils.ts'

const TIME_TAG_PATTERN = /\[(\d+):(\d{2})(?:[.:](\d{2,3}))?\]/g

type LrcRedNodeLink = {
  options?: { lyrics?: Record<string, unknown> }
  proxyManager?: {
    getBestProxy: (
      sourceName: string
    ) => { target?: HttpProxyConfig } | undefined
    report?: (url: string, success: boolean, statusCode: number) => void
  }
}

type ProxyConfig = HttpProxyConfig | string

interface LrcRedDetail {
  isrc?: string
  title?: string
  artist?: string
  sync?: 'word' | 'line' | 'none' | string
  duration?: number
  page?: string
  files?: {
    lrc?: string
    lyricsfile?: string
  }
}

export default class LrcRedLyrics {
  public readonly nodelink: LrcRedNodeLink
  private proxyIndex = 0

  public constructor(nodelink: LrcRedNodeLink) {
    this.nodelink = nodelink
  }

  public async setup(): Promise<boolean> {
    return true
  }

  private _getProxy(): HttpProxyConfig | undefined {
    const sourceConfig = this.nodelink.options?.lyrics?.lrcRed
    const custom =
      typeof sourceConfig === 'object' && sourceConfig !== null
        ? (sourceConfig as { proxy?: ProxyConfig | ProxyConfig[] }).proxy
        : undefined

    if (Array.isArray(custom)) {
      if (custom.length === 0) return undefined
      const item = custom[this.proxyIndex % custom.length]
      this.proxyIndex = (this.proxyIndex + 1) % custom.length
      return typeof item === 'string' ? { url: item } : item
    }

    if (typeof custom === 'string') return { url: custom }
    if (custom) return custom
    return this.nodelink.proxyManager?.getBestProxy('lrcRed')?.target
  }

  private _reportProxy(
    proxy: HttpProxyConfig | undefined,
    success: boolean,
    statusCode: number
  ): void {
    if (proxy?.url) {
      this.nodelink.proxyManager?.report?.(proxy.url, success, statusCode)
    }
  }

  /**
   * Applies line durations based on subsequent line timestamps.
   */
  private _applyLineDurations(lines: LyricsLine[]): LyricsLine[] {
    const sortedLines = [...lines].sort((left, right) => left.time - right.time)

    return sortedLines.map((line, index) => {
      if (line.duration && line.duration > 0) {
        return line
      }
      const nextLine = sortedLines[index + 1]
      return {
        ...line,
        duration:
          nextLine && nextLine.time > line.time ? nextLine.time - line.time : 0
      }
    })
  }

  /**
   * Parses standard and enhanced LRC formatted lyrics line-by-line.
   */
  private _parseLrc(lrc: string): LyricsLine[] {
    const lines: LyricsLine[] = []
    const rawLines = lrc.split(/\r?\n/)

    for (const rawLine of rawLines) {
      const timestamps: number[] = []
      let match = TIME_TAG_PATTERN.exec(rawLine)

      while (match) {
        const minutes = Number.parseInt(match[1] ?? '0', 10)
        const seconds = Number.parseInt(match[2] ?? '0', 10)
        const msText = (match[3] ?? '0').padEnd(3, '0').slice(0, 3)
        const milliseconds = Number.parseInt(msText, 10)

        timestamps.push(minutes * 60_000 + seconds * 1_000 + milliseconds)
        match = TIME_TAG_PATTERN.exec(rawLine)
      }

      TIME_TAG_PATTERN.lastIndex = 0

      if (timestamps.length === 0) continue

      // Strip time tags and inline word tags (<00:10.06>)
      const text = rawLine
        .replace(/\[\d+:\d{2}(?:[.:]\d{2,3})?\]/g, '')
        .replace(/<\d+:\d{2}(?:[.:]\d{2,3})?>/g, '')
        .trim()

      if (text.length === 0) continue

      for (const time of timestamps) {
        lines.push({ text, time, duration: 0 })
      }
    }

    return this._applyLineDurations(lines)
  }

  public async getLyrics(track: TrackInfo): Promise<LyricsResult> {
    const isrc = track.isrc?.replace(/[-\s]/g, '').trim()

    // Strictly focus lookup on ISRC; immediately fallback to other providers if missing
    if (!isrc) {
      return { loadType: 'empty', data: {} }
    }

    const proxy = this._getProxy()
    const headers = {
      accept: 'application/json, text/plain, */*',
      'accept-language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
      'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin'
    }

    const request = async (url: string, referer = 'https://lrc.red/') =>
      makeRequest(url, {
        method: 'GET',
        headers: { ...headers, Referer: referer },
        proxy,
        network: proxy ? { proxy } : undefined
      })

    try {
      const pageUrl = `https://lrc.red/s/${encodeURIComponent(isrc)}`
      const detailResponse = await request(`${pageUrl}.json`, pageUrl)

      if (detailResponse.error || detailResponse.statusCode !== 200) {
        this._reportProxy(proxy, false, detailResponse.statusCode ?? 0)
        return { loadType: 'empty', data: {} }
      }
      this._reportProxy(proxy, true, detailResponse.statusCode ?? 200)

      const detail = (
        typeof detailResponse.body === 'string'
          ? JSON.parse(detailResponse.body)
          : detailResponse.body
      ) as LrcRedDetail

      // If metadata explicitly indicates unsynced (plain/none) or missing LRC file, fallback
      if (detail.sync === 'none' || !detail.files?.lrc) {
        return { loadType: 'empty', data: {} }
      }

      const lrcResponse = await request(detail.files.lrc, pageUrl)
      if (
        lrcResponse.error ||
        lrcResponse.statusCode !== 200 ||
        !lrcResponse.body
      ) {
        this._reportProxy(proxy, false, lrcResponse.statusCode ?? 0)
        return { loadType: 'empty', data: {} }
      }
      this._reportProxy(proxy, true, lrcResponse.statusCode)

      const bodyText =
        typeof lrcResponse.body === 'string'
          ? lrcResponse.body
          : String(lrcResponse.body)

      const lines = this._parseLrc(bodyText)

      // If no valid synced lines were found, return empty to fallback to other providers
      if (!lines.length || !lines.some((line) => line.time > 0)) {
        return { loadType: 'empty', data: {} }
      }

      return {
        loadType: 'lyrics',
        data: {
          name: detail.title || track.title,
          synced: true,
          lines,
          attribution: {
            name: 'lrc.red',
            url:
              detail.page ??
              `https://lrc.red/s/${encodeURIComponent(isrc)}`
          }
        }
      }
    } catch (error) {
      logger(
        'debug',
        'Lyrics',
        `lrc.red lookup failed: ${error instanceof Error ? error.message : String(error)}`
      )
      return { loadType: 'empty', data: {} }
    }
  }
}
