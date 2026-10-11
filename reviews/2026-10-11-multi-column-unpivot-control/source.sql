DATA wide = SELECT item.id AS id, item.jan_amount AS jan_amount, item.jan_note AS jan_note, item.feb_amount AS feb_amount, item.feb_note AS feb_note FROM UNNEST(@rows) item;
SELECT id,amount,note,month
FROM wide
UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,feb_note) AS 'Feb'))
ORDER BY id,month
