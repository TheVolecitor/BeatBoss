import json
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

har_file = r'C:\Users\Aaradhya and Ayush\Downloads\pookie.har'

with open(har_file, 'r', encoding='utf-8') as f:
    data = json.load(f)

entries = data['log']['entries']

for e in entries:
    req = e['request']
    res = e['response']
    url = req['url']
    
    if req['method'] == 'GET' and 'DB_users' in url:
        content = res['content'].get('text', '')
        if content:
            try:
                data = json.loads(content)
                if 'items' in data and len(data['items']) > 0:
                    item = data['items'][0]
                    playlists = item.get('user_playlists')
                    if playlists and isinstance(playlists, str):
                        playlists = json.loads(playlists)
                    
                    if playlists:
                        # Show first playlist
                        first_id = list(playlists.keys())[0]
                        print(f"Sample Playlist ({first_id}):")
                        # Show keys and a bit of data
                        p = playlists[first_id]
                        print("Playlist Keys:", list(p.keys()))
                        if 'tracks' in p and p['tracks']:
                            print(f"First track in playlist ({len(p['tracks'])} tracks total):")
                            print(json.dumps(p['tracks'][0], indent=2))
            except Exception as ex:
                print("Error:", ex)
        print("-" * 60)
