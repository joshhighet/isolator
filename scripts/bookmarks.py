import csv
import os

timestamp = "1704067200"

bookmarks = []
csv_path = '../bookmarks.csv'

if os.path.exists(csv_path):
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            name = row['name']
            url = row['url']
            if '.onion' not in url:
                name = "c-" + name
            bookmark = f'<DT><A HREF="{url}" ADD_DATE="{timestamp}" LAST_MODIFIED="{timestamp}">{name}</A>'
            bookmarks.append(bookmark)
else:
    print(f"CSV file {csv_path} not found")

header = f'''<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 ADD_DATE="{timestamp}" LAST_MODIFIED="{timestamp}" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Toolbar</H3>
    <DL><p>
'''

footer = '''
    </DL><p>
</DL><p>
'''

content = header + '        ' + '\n        '.join(bookmarks) + footer

with open('../bookmarks.html', 'w', encoding='utf-8') as f:
    f.write(content)

print("bookmarks file saved as bookmarks.html")
