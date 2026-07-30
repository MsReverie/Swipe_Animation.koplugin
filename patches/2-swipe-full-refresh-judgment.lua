--[[
    2-swipe-full-refresh-judgment.lua

    Extract the full-refresh decision logic. Prefer original data sources, but trigger
    Screen:refreshFull / refreshPartial directly (because we are inside _repaint,
    where setDirty would be deferred and ineffective).

    Changes (phase 1 + hot-path optimization):
    - shouldForceFullAfterAnimation can now be called before the animation; prev_page is passed by the caller
    - forceFullAndReset supports mild global refresh (consistent with performClearing)
    - ReaderUI is required at module level to avoid repeated requires on every animation hot path
]]

local Device = require("device")
local Screen = Device.screen
local logger = require("logger")
-- Module-level cache to avoid repeated requires on the _repaint hot path
local ReaderUI = require("apps/reader/readerui")

local SwipeFullRefresh = {}

---------------------------------------------------------------
-- 1. Whether to skip the animation and perform a clearing refresh
---------------------------------------------------------------
function SwipeFullRefresh.shouldDoClearing(self)
    if not (self.FULL_REFRESH_COUNT and self.FULL_REFRESH_COUNT > 0) then
        return false
    end

    self._swipe_full_refresh_count = (self._swipe_full_refresh_count or 0) + 1

    if self._swipe_full_refresh_count >= self.FULL_REFRESH_COUNT then
        self._swipe_full_refresh_count = 0
        return true
    end
    return false
end

---------------------------------------------------------------
-- 2. Perform the clearing refresh (supports mild global refresh)
---------------------------------------------------------------
function SwipeFullRefresh.performClearing(self, screen_w, screen_h)
    local mild = G_reader_settings:isTrue("swipe_animation_mild_global_refresh")

    if mild then
        Screen:refreshPartial(0, 0, screen_w, screen_h)
        logger.dbg("SwipeFullRefresh: mild (partial) clearing refresh")
    else
        Screen:refreshFull(0, 0, screen_w, screen_h)
        logger.dbg("SwipeFullRefresh: full clearing refresh")
    end

    self.refresh_count = 0
    self._refresh_stack = {}
end

---------------------------------------------------------------
-- 3. Whether a forced full refresh is needed (images / chapter boundaries)
--    Can be called before the animation; accurate prev_page is required
--    to correctly detect forward/backward chapter boundaries
---------------------------------------------------------------
function SwipeFullRefresh.shouldForceFullAfterAnimation(self, prev_page)
    local instance = ReaderUI.instance
    if not instance then
        return false
    end

    -- ===== Images(ReaderView:paintTo) =====
    local view = instance.view
    if view then
        local curr_coverage = view.img_coverage or 0
        local prev_coverage = view._swipe_prev_img_coverage or 0
        local coverage_diff = math.abs(curr_coverage - prev_coverage)

        view._swipe_prev_img_coverage = curr_coverage

        if curr_coverage >= 0.075 or coverage_diff >= 0.075 then
            if G_reader_settings:nilOrTrue("refresh_on_pages_with_images") then
                return true
            end
        end
    end

    -- ===== Chapters (faithful recreation of ReaderToc:onPageUpdate) =====
    local toc = instance.toc
    if not toc then return false end

    if not (self.FULL_REFRESH_COUNT == -1 or G_reader_settings:isTrue("refresh_on_chapter_boundaries")) then
        return false
    end

    local paging = instance.paging
    local rolling = instance.rolling
    local current_page = (paging and paging.current_page) or (rolling and rolling.current_page)

    if not current_page then return false end

    -- If prev_page was not provided, fall back to toc.pageno
    -- (which may already be the new page, so less accurate)
    prev_page = prev_page or toc.pageno

    local flash_on_second = G_reader_settings:nilOrFalse("no_refresh_on_second_chapter_page")
    local paging_forward, paging_backward

    if flash_on_second and prev_page then
        if current_page > prev_page then
            paging_forward = true
        elseif current_page < prev_page then
            paging_backward = true
        end
    end

    if paging_backward and toc:isChapterEnd(current_page) then
        return true
    elseif toc:isChapterStart(current_page) then
        return true
    elseif paging_forward and toc:isChapterSecondPage(current_page) then
        return true
    end

    return false
end


---------------------------------------------------------------
-- 4. Actually trigger the full refresh
--    Supports mild global refresh, consistent with performClearing
---------------------------------------------------------------
function SwipeFullRefresh.forceFullAndReset(self, screen_w, screen_h)
    -- We are inside _repaint, so we must refresh directly;
    -- setDirty would be deferred to the next frame and become ineffective
    local mild = G_reader_settings:isTrue("swipe_animation_mild_global_refresh")

    if mild then
        Screen:refreshPartial(0, 0, screen_w, screen_h)
        logger.dbg("SwipeFullRefresh: mild (partial) forced refresh (image/chapter)")
    else
        Screen:refreshFull(0, 0, screen_w, screen_h)
        logger.dbg("SwipeFullRefresh: forced full refresh (image/chapter)")
    end

    self._swipe_full_refresh_count = 0
    self.refresh_count = 0
    self._refresh_stack = {}
end

_G.SwipeFullRefresh = SwipeFullRefresh
return SwipeFullRefresh