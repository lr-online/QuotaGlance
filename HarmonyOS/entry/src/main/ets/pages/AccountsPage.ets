import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AccountService } from '../services/AccountService';
import { Account, AccountStore } from '../storage/AccountStore';
import { providerDisplayName } from '../providers/ProviderCatalog';
import { friendlyErrorText } from '../utils/ErrorMapping';

// Row gap mirrors List({ space: 12 }). Used with the measured row height to
// convert pan offsets into whole-row steps. The estimate is only a fallback
// before the first onAreaChange lands (drags can't start that early anyway).
const LIST_ROW_GAP: number = 12;
const ESTIMATED_ROW_STRIDE: number = 92;

@Entry
@Component
struct AccountsPage {
  @State accounts: Account[] = [];
  // -1 = not dragging. While dragging this is the dragged row's CURRENT index
  // (it moves as the row is spliced past its neighbours).
  @State draggingIndex: number = -1;
  // Visual follow-the-finger offset of the dragged row, minus the distance
  // already absorbed by splices (each splice moves the row one stride in
  // layout, so the translate compensates to keep it under the finger).
  @State dragOffsetY: number = 0;
  private dragStartIndex: number = -1;
  private dragAppliedSteps: number = 0;
  private dragMoved: boolean = false;
  private rowHeight: number = 0;

  onPageShow(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const service = await AccountService.create(context);
    this.accounts = await service.loadAccounts();
  }

  private async setEnabled(account: Account, enabled: boolean): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const store = await AccountStore.create(context);
      const updated: Account = {
        id: account.id,
        displayName: account.displayName,
        provider: account.provider,
        detectedProfile: account.detectedProfile,
        isEnabled: enabled,
        sortOrder: account.sortOrder,
        lowBalanceThreshold: account.lowBalanceThreshold
      };
      await store.update(updated);
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    await this.reload();
  }

  private confirmDelete(account: Account): void {
    const context = getContext(this) as common.UIAbilityContext;
    AlertDialog.show({
      title: context.resourceManager.getStringSync($r('app.string.delete_confirm_title').id),
      message: context.resourceManager.getStringSync($r('app.string.delete_confirm_message').id),
      primaryButton: {
        value: context.resourceManager.getStringSync($r('app.string.cancel').id),
        action: () => {
        }
      },
      secondaryButton: {
        value: context.resourceManager.getStringSync($r('app.string.delete').id),
        fontColor: $r('app.color.danger'),
        action: () => {
          this.deleteAccount(account);
        }
      }
    });
  }

  private async deleteAccount(account: Account): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const service = await AccountService.create(context);
      await service.deleteAccount(account.id);
    } catch (error) {
      promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
    }
    await this.reload();
  }

  // Long-press the handle starts a drag; the sequenced pan then live-reorders
  // one row at a time. Dropping persists via saveAll (which re-sorts by
  // sortOrder, so sortOrder is re-sequenced to the array order first —
  // persisting stale values would silently undo the drop).
  private rowStride(): number {
    return (this.rowHeight > 0 ? this.rowHeight : ESTIMATED_ROW_STRIDE) + LIST_ROW_GAP;
  }

  private startDrag(index: number): void {
    this.dragStartIndex = index;
    this.draggingIndex = index;
    this.dragAppliedSteps = 0;
    this.dragOffsetY = 0;
    this.dragMoved = false;
  }

  private updateDrag(offsetY: number): void {
    if (this.draggingIndex < 0) {
      return;
    }
    const stride = this.rowStride();
    const minOffset = -this.dragStartIndex * stride;
    const maxOffset = (this.accounts.length - 1 - this.dragStartIndex) * stride;
    const clamped = Math.min(Math.max(offsetY, minOffset), maxOffset);
    let desired = Math.round(clamped / stride);
    while (desired > this.dragAppliedSteps) {
      this.swapDragged(1);
    }
    while (desired < this.dragAppliedSteps) {
      this.swapDragged(-1);
    }
    this.dragOffsetY = clamped - this.dragAppliedSteps * stride;
  }

  private swapDragged(direction: number): void {
    const from = this.draggingIndex;
    const to = from + direction;
    if (to < 0 || to >= this.accounts.length) {
      return;
    }
    const moved = this.accounts.splice(from, 1);
    this.accounts.splice(to, 0, moved[0]);
    this.draggingIndex = to;
    this.dragAppliedSteps += direction;
    this.dragMoved = true;
  }

  private endDrag(): void {
    if (this.draggingIndex < 0) {
      return;
    }
    this.draggingIndex = -1;
    this.dragStartIndex = -1;
    this.dragAppliedSteps = 0;
    this.dragOffsetY = 0;
    if (this.dragMoved) {
      this.dragMoved = false;
      this.persistOrder();
    }
  }

  private persistOrder(): void {
    for (let i = 0; i < this.accounts.length; i++) {
      this.accounts[i].sortOrder = i;
    }
    const context = getContext(this) as common.UIAbilityContext;
    AccountStore.create(context)
      .then((store: AccountStore) => store.saveAll(this.accounts))
      .catch((error: Object) => {
        promptAction.showToast({ message: friendlyErrorText(context, (error as Error).message) });
      });
  }

  @Builder
  accountRow(account: Account, index: number) {
    Row() {
      // Drag handle. priorityGesture so the handle's long-press+pan wins over
      // the List's own scroll recogniser (equivalent to disabling List scroll
      // during the drag, but without killing the in-flight pan, which
      // .enabled(false) would do).
      Text('≡')
        .fontSize(16)
        .fontColor($r('app.color.textSecondary'))
        .padding({ left: 2, right: 10, top: 6, bottom: 6 })
        .priorityGesture(
          GestureGroup(GestureMode.Sequence,
            LongPressGesture()
              .onAction(() => {
                this.startDrag(index);
              }),
            PanGesture()
              .onActionUpdate((event?: GestureEvent) => {
                if (event !== undefined) {
                  this.updateDrag(event.offsetY);
                }
              })
              .onActionEnd(() => {
                this.endDrag();
              })
              .onActionCancel(() => {
                this.endDrag();
              })
          )
        )

      Column({ space: 6 }) {
        Text(account.displayName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.textPrimary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(providerDisplayName(getContext(this), account.provider))
          .fontSize(11)
          .fontColor($r('app.color.accentTeal'))
          .backgroundColor($r('app.color.accentTealTint'))
          .borderRadius(6)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: account.isEnabled })
        .selectedColor($r('app.color.accentTeal'))
        .onChange((isOn: boolean) => {
          this.setEnabled(account, isOn);
        })

      Text($r('app.string.delete'))
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .padding({ left: 12, top: 6, right: 4, bottom: 6 })
        .onClick(() => {
          this.confirmDelete(account);
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.cardBackground'))
    .borderRadius(14)
    // Drag visuals: lift (scale + shadow + zIndex) and follow the finger via
    // translate; other rows stay put and make room as splices happen.
    .scale(index === this.draggingIndex ? { x: 1.04, y: 1.04 } : { x: 1, y: 1 })
    .translate({ y: index === this.draggingIndex ? this.dragOffsetY : 0 })
    .zIndex(index === this.draggingIndex ? 1 : 0)
    .shadow(index === this.draggingIndex
      ? { radius: 18, color: '#33000000', offsetX: 0, offsetY: 6 }
      : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      if (this.rowHeight <= 0) {
        this.rowHeight = newArea.height as number;
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor($r('app.color.textPrimary'))
          .padding({ right: 12, top: 2, bottom: 2 })
          .onClick(() => {
            router.back();
          })
        Text($r('app.string.manage_accounts'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.textPrimary'))
        Blank()
        Text($r('app.string.add_account'))
          .fontSize(15)
          .fontColor($r('app.color.accentTeal'))
          .padding(4)
          .onClick(() => {
            router.pushUrl({ url: 'pages/AccountEditorPage' });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 20 })

      if (this.accounts.length === 0) {
        Column() {
          Text($r('app.string.empty_accounts'))
            .fontSize(15)
            .fontColor($r('app.color.textSecondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.accounts, (account: Account, index: number) => {
            ListItem() {
              this.accountRow(account, index)
            }
          }, (account: Account) => account.id)
        }
        .width('100%')
        .constraintSize({ maxWidth: 560 })
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.appBackground'))
  }
}
