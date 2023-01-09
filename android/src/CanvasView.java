import android.view.View;
import android.graphics.Canvas;
import android.content.Context;

public class CanvasView extends View {

	public CanvasView(Context context) {
		super(context);
		this.setWillNotDraw(false);
	}

	@Override
	protected void onDraw(Canvas canvas) {
		onDraw0(canvas);
	}

	native private void onDraw0(Canvas canvas);
};
