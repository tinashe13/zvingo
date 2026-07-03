import zipfile
import xml.etree.ElementTree as ET
import sys
import os

def read_docx(path):
    print(f"Attempting to read: {path}")
    if not os.path.exists(path):
        print(f"File not found: {path}")
        # Try looking in current directory
        cwd_files = os.listdir('.')
        print(f"Files in current directory: {cwd_files}")
        return

    try:
        with zipfile.ZipFile(path) as z:
            xml_content = z.read('word/document.xml')
        
        tree = ET.fromstring(xml_content)
        text = []
        
        forBM = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
        
        for elem in tree.iter():
            if elem.tag.endswith('}t'):
                if elem.text:
                    text.append(elem.text)
            elif elem.tag.endswith('}p'):
                text.append('\n')
            elif elem.tag.endswith('}br'):
                text.append('\n')
            elif elem.tag.endswith('}tab'):
                text.append('\t')
                
        print(''.join(text))
    except Exception as e:
        print(f"Error reading docx: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python read_docx.py <filename>")
    else:
        # Require quotes in shell, but just in case, join args
        filename = " ".join(sys.argv[1:])
        read_docx(filename)
