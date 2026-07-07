-- Target file to enable page turn animation for PDFs/CBZs in KOReader paged mode
local ReaderPaging = require("apps/reader/modules/readerpaging")
local Event = require("ui/event")

local original_gotoPage = ReaderPaging._gotoPage

function ReaderPaging:_gotoPage(number, orig_mode)
    -- Check if we are turning a page and not in scroll mode
    if self.current_page and self.current_page > 0 and number ~= self.current_page and not self.view.page_scroll then
        if G_reader_settings:isTrue("swipe_animations") then
            local forward = number > self.current_page
            self.ui:handleEvent(Event:new("PageChangeAnimation", forward))
        end
    end
    -- Call the original page turn logic
    return original_gotoPage(self, number, orig_mode)
end
