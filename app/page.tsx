"use client"

import { useState, useMemo, useEffect, useCallback } from "react"
import { Search, Calendar, Trophy, Tv, Clock, ChevronDown } from "lucide-react"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card } from "@/components/ui/card"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
// Frontend now relies solely on backend API; no local JSON fallback

interface Match {
  date_text: string
  time: string
  home: string
  away: string
  teams: string
  competition: string | null
  channels: string[] | null
  raw: string
}

export default function QualCanal() {
  const [searchQuery, setSearchQuery] = useState("")
  const [selectedDate, setSelectedDate] = useState("Todas as datas")
  const [selectedLeague, setSelectedLeague] = useState("Todas as ligas")
  const [selectedChannel, setSelectedChannel] = useState("Todos os canais")
  const [matches, setMatches] = useState<Match[]>([])
  const [isLoading, setIsLoading] = useState<boolean>(true)
  const [error, setError] = useState<string | null>(null)

  const loadMatches = useCallback(async (signal?: AbortSignal) => {
    setIsLoading(true)
    setError(null)
    try {
      console.info("[QualCanal] fetch:start", { url: "/api/matches?refresh=1" })
      const res = await fetch(`/api/matches?refresh=1`, { signal })
      console.info("[QualCanal] fetch:response", { status: res.status, ok: res.ok, redirected: res.redirected, url: res.url })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      console.info("[QualCanal] fetch:json", { keys: Object.keys(data || {}), sample: Array.isArray(data?.matches) ? data.matches[0] : undefined })
      const payload = Array.isArray(data?.matches) ? data.matches : (Array.isArray(data) ? data : null)
      if (!payload) throw new Error("Invalid response payload")
      const normalized: Match[] = (payload as Match[]).map((m) => ({
        date_text: m.date_text || "",
        time: m.time || "",
        home: m.home || "",
        away: m.away || "",
        teams: m.teams || `${m.home || ""} - ${m.away || ""}`.trim(),
        competition: m.competition ?? "",
        channels: (m.channels || []).map((c) => (c || "").trim()).filter(Boolean),
        raw: m.raw || "",
      }))
      console.info("[QualCanal] fetch:normalized", { count: normalized.length })
      setMatches(normalized)
    } catch (err) {
      console.error("[QualCanal] fetch:error", err)
      setError("Falha ao carregar dados do backend.")
      setMatches([])
    } finally {
      console.info("[QualCanal] fetch:done")
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    const controller = new AbortController()
    loadMatches(controller.signal)
    return () => controller.abort()
  }, [loadMatches])

  // Get unique values for filters
  const uniqueDates = useMemo(() => {
    const dates = [...new Set(matches.map((match) => match.date_text))]
    const list = ["Todas as datas", ...dates]
    console.debug("[QualCanal] memo:uniqueDates", { count: list.length - 1 })
    return list
  }, [matches])

  const uniqueLeagues = useMemo(() => {
    const leagues = [
      ...new Set(
        matches
          .map((match) => {
            const competition = (match.competition || "").trim()
            if (competition.includes("Liga")) {
              return competition.split(" ").slice(-2).join(" ")
            }
            return competition
          })
          .filter(Boolean),
      ),
    ]
    const list = ["Todas as ligas", ...leagues]
    console.debug("[QualCanal] memo:uniqueLeagues", { count: list.length - 1 })
    return list
  }, [matches])

  const uniqueChannels = useMemo(() => {
    const channels = [...new Set(matches.flatMap((match) => match.channels || []))]
    const list = ["Todos os canais", ...channels]
    console.debug("[QualCanal] memo:uniqueChannels", { count: list.length - 1 })
    return list
  }, [matches])

  // Filter matches
  const filteredMatches = useMemo(() => {
    const result = matches.filter((match) => {
      const matchesSearch =
        searchQuery === "" ||
        (match.home || "").toLowerCase().includes(searchQuery.toLowerCase()) ||
        (match.away || "").toLowerCase().includes(searchQuery.toLowerCase()) ||
        (match.competition || "").toLowerCase().includes(searchQuery.toLowerCase())

      const matchesDate = selectedDate === "Todas as datas" || match.date_text === selectedDate

      const matchesLeague = selectedLeague === "Todas as ligas" || (match.competition || "").includes(selectedLeague)

      const matchesChannel = selectedChannel === "Todos os canais" || (match.channels || []).includes(selectedChannel)

      return matchesSearch && matchesDate && matchesLeague && matchesChannel
    })
    console.debug("[QualCanal] memo:filteredMatches", { total: matches.length, filtered: result.length })
    return result
  }, [matches, searchQuery, selectedDate, selectedLeague, selectedChannel])

  useEffect(() => {
    console.info("[QualCanal] state:matches", { count: matches.length })
  }, [matches])

  // Check if match is live (simplified logic - matches with "hoje" are considered live)
  const isLive = (match: Match) => match.raw.includes("hoje")

  const liveCount = filteredMatches.filter(isLive).length
  const upcomingCount = filteredMatches.length - liveCount

  const getChannelColor = (channel: string) => {
    const colors: Record<string, { bg: string; text: string }> = {
      "dazn 1": { bg: "bg-yellow-100", text: "text-yellow-800" },
      "dazn 4": { bg: "bg-yellow-100", text: "text-yellow-800" },
      "Sport.Tv1": { bg: "bg-blue-100", text: "text-blue-800" },
      "Sport.Tv2": { bg: "bg-blue-100", text: "text-blue-800" },
      "Sport.Tv3": { bg: "bg-blue-100", text: "text-blue-800" },
      "Sport.Tv5": { bg: "bg-blue-100", text: "text-blue-800" },
      "Canal 11": { bg: "bg-green-100", text: "text-green-800" },
      "Benfica.Tv": { bg: "bg-red-100", text: "text-red-800" },
      "C11 online": { bg: "bg-emerald-100", text: "text-emerald-800" },
    }
    return colors[channel] || { bg: "bg-gray-100", text: "text-gray-800" }
  }

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white">
        <div className="flex flex-col items-center gap-3 text-gray-700">
          <div className="h-8 w-8 rounded-full border-2 border-gray-300 border-t-gray-900 animate-spin" />
          <span className="text-sm">A carregar dados…</span>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-white">
        <div className="flex flex-col items-center gap-4">
          <p className="text-sm text-red-600">{error}</p>
          <button
            onClick={() => loadMatches()}
            className="px-4 py-2 rounded bg-gray-900 text-white text-sm"
          >
            Tentar novamente
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-white">
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-6 py-6">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center space-x-3">
              <div className="bg-black rounded-lg p-2">
                <Calendar className="h-6 w-6 text-white" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-gray-900">QualCanal</h1>
                <p className="text-sm text-gray-500">Sports Broadcasting</p>
              </div>
            </div>

            <div className="relative max-w-md">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
              <Input
                placeholder="Pesquisar equipas ou competições…"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10 w-80"
              />
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-6 py-6">
        <div className="flex flex-wrap items-center gap-3 mb-6">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="outline"
                className="flex items-center gap-2 bg-gray-50 border-gray-200 hover:bg-gray-100"
              >
                <Calendar className="h-4 w-4" />
                {selectedDate}
                <ChevronDown className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              {uniqueDates.map((date) => (
                <DropdownMenuItem key={date} onClick={() => setSelectedDate(date)}>
                  {date}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="outline"
                className="flex items-center gap-2 bg-gray-50 border-gray-200 hover:bg-gray-100"
              >
                <Trophy className="h-4 w-4" />
                {selectedLeague}
                <ChevronDown className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              {uniqueLeagues.map((league) => (
                <DropdownMenuItem key={league} onClick={() => setSelectedLeague(league)}>
                  {league}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="outline"
                className="flex items-center gap-2 bg-gray-50 border-gray-200 hover:bg-gray-100"
              >
                <Tv className="h-4 w-4" />
                {selectedChannel}
                <ChevronDown className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent>
              {uniqueChannels.map((channel) => (
                <DropdownMenuItem key={channel} onClick={() => setSelectedChannel(channel)}>
                  {channel}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <div className="flex items-center gap-6 mb-6 p-4 bg-gray-50 rounded-lg">
          <div className="flex items-center gap-2">
            <Calendar className="h-4 w-4 text-gray-600" />
            <span className="text-sm text-gray-700">
              Total: <strong className="text-gray-900">{filteredMatches.length}</strong> jogos
            </span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-red-500 rounded-full"></div>
            <span className="text-sm text-gray-700">
              Ao vivo: <strong className="text-red-600">{liveCount}</strong>
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4 text-blue-600" />
            <span className="text-sm text-gray-700">
              Próximos: <strong className="text-blue-600">{upcomingCount}</strong>
            </span>
          </div>
        </div>

        <div className="hidden lg:block">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-6 py-4 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    DATA & HORA
                  </th>
                  <th className="px-6 py-4 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    EQUIPAS
                  </th>
                  <th className="px-6 py-4 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    COMPETIÇÃO
                  </th>
                  <th className="px-6 py-4 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    CANAIS
                  </th>
                  <th className="px-6 py-4 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    ESTADO
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {filteredMatches.map((match, index) => (
                  <tr key={index} className="hover:bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm">
                        <div className="font-medium text-gray-900">{match.date_text}</div>
                        <div className="flex items-center gap-1 text-gray-500 mt-1">
                          <Clock className="h-3 w-3" />
                          {match.time}
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="text-sm font-bold text-gray-900">
                        {match.home} <span className="text-gray-500">vs</span> {match.away}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2 text-sm text-gray-900">
                        <Trophy className="h-4 w-4 text-gray-400" />
                        {match.competition}
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex flex-wrap gap-1">
                        {match.channels.map((channel, idx) => {
                          const channelColors = getChannelColor(channel)
                          return (
                            <Badge
                              key={idx}
                              className={`${channelColors.bg} ${channelColors.text} font-bold text-xs px-2 py-1 rounded border-0`}
                            >
                              {channel}
                            </Badge>
                          )
                        })}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {isLive(match) ? (
                        <div className="flex items-center gap-2">
                          <div className="w-2 h-2 bg-red-500 rounded-full"></div>
                          <span className="text-sm font-medium text-red-600">AO VIVO</span>
                        </div>
                      ) : (
                        <div className="flex items-center gap-2">
                          <div className="w-2 h-2 bg-gray-400 rounded-full"></div>
                          <span className="text-sm text-gray-500">AGENDADO</span>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Mobile Cards */}
        <div className="lg:hidden space-y-4">
          {filteredMatches.map((match, index) => (
            <Card key={index} className={`p-4 ${isLive(match) ? "border-l-4 border-red-500" : ""}`}>
              <div className="flex justify-between items-start mb-3">
                <div className="text-sm">
                  <div className="font-medium text-gray-900">{match.date_text}</div>
                  <div className="flex items-center gap-1 text-gray-500">
                    <Clock className="h-3 w-3" />
                    {match.time}
                  </div>
                </div>
                {isLive(match) ? (
                  <Badge className="bg-red-500 text-white text-xs">AO VIVO</Badge>
                ) : (
                  <Badge variant="secondary" className="text-xs">
                    AGENDADO
                  </Badge>
                )}
              </div>

              <div className="mb-3">
                <div className="font-bold text-gray-900">
                  {match.home} <span className="text-gray-500">vs</span> {match.away}
                </div>
              </div>

              <div className="flex items-center gap-1 text-sm text-gray-900 mb-3">
                <Trophy className="h-4 w-4 text-yellow-500" />
                {match.competition}
              </div>

              <div className="flex flex-wrap gap-1">
                {match.channels.map((channel, idx) => {
                  const channelColors = getChannelColor(channel)
                  return (
                    <Badge
                      key={idx}
                      className={`${channelColors.bg} ${channelColors.text} font-bold text-xs flex items-center gap-1 border-0`}
                    >
                      <Tv className="h-3 w-3" />
                      {channel}
                    </Badge>
                  )
                })}
              </div>
            </Card>
          ))}
        </div>

        {filteredMatches.length === 0 && (
          <div className="text-center py-12">
            <p className="text-gray-500">Nenhum jogo encontrado com os filtros selecionados.</p>
          </div>
        )}
      </div>
    </div>
  )
}
