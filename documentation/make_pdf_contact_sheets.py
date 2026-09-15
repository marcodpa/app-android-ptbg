from pathlib import Path

from PIL import Image, ImageDraw


source = Path("tmp/pdfs/informe_visual_ster")
pages = sorted(source.glob("page-*.png"))
for group_index in range(0, len(pages), 5):
    group = pages[group_index:group_index + 5]
    thumbs = []
    for page in group:
        image = Image.open(page).convert("RGB")
        image.thumbnail((340, 440))
        canvas = Image.new("RGB", (360, 480), "white")
        canvas.paste(image, ((360 - image.width) // 2, 25))
        ImageDraw.Draw(canvas).text((12, 8), page.stem, fill="black")
        thumbs.append(canvas)
    sheet = Image.new("RGB", (360 * len(thumbs), 480), "#D9E2EE")
    for index, thumb in enumerate(thumbs):
        sheet.paste(thumb, (index * 360, 0))
    sheet.save(source / f"contact-{group_index // 5 + 1}.png")
