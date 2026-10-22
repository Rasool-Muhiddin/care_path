class ApiNoStoreMiddleware:
    """ردود /api/ فيها بيانات طبية: لا تُخزَّن في cache المتصفح (نسخة الويب
    على iPhone) ولا في Cloudflare. الرد الذي يحدد Cache-Control بنفسه (مثل
    الملف الصوتي: private, no-store) يبقى كما هو. تطبيقات أندرويد/iOS لا
    تخزّن ردود Dio أصلاً، فلا تغيير عليها."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        if request.path.startswith('/api/') and not response.has_header('Cache-Control'):
            response['Cache-Control'] = 'no-store'
        return response
