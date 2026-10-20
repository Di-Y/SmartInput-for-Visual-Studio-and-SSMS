-- 此文件用于 SSMS / Visual Studio 的编辑器交互检查，不参与正式构建。
-- 在下列每一处输入，光标所在区域决定推荐的输入法状态：
--   普通 T-SQL 代码、[方括号] 与 "双引号" 标识符（QUOTED_IDENTIFIER ON，默认） -> 英文
--   SET QUOTED_IDENTIFIER OFF 后，"双引号" 是字符串：含汉字 -> 中文、纯英文 -> 英文
--   -- 行注释、/* 块注释 */（可嵌套）              -> 中文
--   含汉字的单引号字符串 '...'（可写 N'...'）       -> 中文
--   空字符串或纯英文字符串、仅 emoji               -> 英文

/* ========================================================================
   块注释：这里应保持中文，可以连续输入中文说明。
   T-SQL 的块注释支持嵌套：/* 内层注释 */ 外层仍处于注释中。
   ======================================================================== */

SET NOCOUNT ON;

-- 查询订单：下面的关键字、表名与列名区域都应保持英文。
SELECT
    o.OrderId,
    o.TotalAmount,
    ROW_NUMBER() OVER (PARTITION BY o.CustomerId ORDER BY o.CreatedAt DESC) AS RowNo
FROM dbo.[Order] AS o                 -- 方括号标识符即使写中文也按英文处理：[订单表]
INNER JOIN dbo."Customer" AS c        -- 双引号标识符（QUOTED_IDENTIFIER ON）同样按英文
    ON c.Id = o.CustomerId
WHERE o.Status = N'已支付'             -- 含汉字的字符串 -> 中文
  AND o.Remark = 'pending review'     -- 纯英文字符串 -> 英文
  AND o.Delta  = -1                   -- 负数的单减号不是注释，仍是代码 -> 英文
  AND o.Note   = N'数量：''两件''';     -- '' 是转义单引号，整体仍是一个含汉字字符串

-- 字符串可以跨越多行，跨行期间在字符串内仍按字符串规则判断：
DECLARE @sql nvarchar(max) = N'
SELECT ''中文'' AS Message,          -- 字符串内部的 -- 与 /* 不会被当作注释
       1        AS Number;
';

-- 空字符串与仅 emoji 的字符串推荐英文，避免在不需要中文时被切换：
DECLARE @empty nvarchar(10) = N'';
DECLARE @emoji nvarchar(10) = N'😀';

-- QUOTED_IDENTIFIER 开关示例（连接 / 批处理默认 ON）：
SET QUOTED_IDENTIFIER ON;
SELECT "CustomerName" AS ColName;   -- ON：双引号是标识符，即使写汉字也按英文

SET QUOTED_IDENTIFIER OFF;
SELECT "中文提示" AS Message;        -- OFF：双引号是字符串字面量，含汉字 -> 中文
SELECT "english text" AS Msg2;       -- OFF：纯英文双引号字符串 -> 英文
SET QUOTED_IDENTIFIER ON;            -- 恢复 ON 后，双引号重新按标识符处理 -> 英文

/*
  手动切到英文输入中文注释，可检查红色光标与“保持当前输入态”行为；
  把光标移到其它区域后，手动覆盖会自动清除。
*/
SELECT @empty AS EmptyValue, @emoji AS EmojiValue;
