# pw-dump JSON in, one line per app reading an xdg-desktop-portal-hyprland
# screencast stream out (browser shares, OBS, Zoom, portal recorders).
(map(select(.type == "PipeWire:Interface:Node")) | map({key: (.id | tostring), value: .info.props}) | from_entries) as $nodes
| [ .[] | select(.type == "PipeWire:Interface:Link") | .info
    | select(($nodes[.["output-node-id"] | tostring] // {})
        | ((."node.name" // "") | startswith("xdph"))
          or ((."application.process.binary" // "") | test("xdg-desktop-portal")))
    | ($nodes[.["input-node-id"] | tostring] // {})
    | ."application.name" // ."application.process.binary" // ."node.name" // "Unknown app" ]
| unique[] | tostring | gsub("[\r\n\t]"; " ")
