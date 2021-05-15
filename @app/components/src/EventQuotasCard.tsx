import React from 'react'
import { EventPage_EventFragment, Registration } from '@app/graphql';
import { Button, Card } from 'antd';
import useBreakpoint from 'antd/lib/grid/hooks/useBreakpoint';
import useTranslation from 'next-translate/useTranslation';

import { Link, ProgressBar } from '.';

interface EventQuotasCardProps {
  event: EventPage_EventFragment;
  registrations: Registration[]
}

export const EventQuotasCard: React.FC<EventQuotasCardProps> = ({ event, registrations }) => {
  const { t, lang } = useTranslation("events");
  const screens = useBreakpoint();
  const isMobile = screens["xs"];
  const {
    id: eventId,
    signupClosed,
    signupUpcoming,
    quotas,
  } = event;

  return (
    <Card
      data-cy="eventpage-quotas-card"
      style={{
        marginLeft: !isMobile ? "1rem" : undefined,
        marginBottom: isMobile ? "1rem" : undefined,
        width: "100%",
      }}
      title={t("register:sidebar.title")}
      bordered
    >
      {quotas?.nodes.map((quota, i) => {
        const { id: quotaId, title, size } = quota;
        const totalCount = registrations.filter(
          (r) => r?.quota?.id === quotaId
        ).length;
        const percentageFilled = Math.round((totalCount / size) * 100);

        return (
          <div key={quotaId} style={{ paddingBottom: 12 }}>
            <Link
              href={{
                pathname: "/event/register/[eventId]/q/[quotaId]",
                query: { eventId, quotaId },
              }}
            >
              <Button
                data-cy={`eventpage-quotas-link-${i}`}
                disabled={signupClosed! || signupUpcoming!}
                target="a"
                block
              >
                {title[lang]}
              </Button>
            </Link>
            <ProgressBar
              filled={totalCount}
              percentageFilled={percentageFilled}
              size={size}
            />
          </div>
        );
      })}
    </Card>
  )
}
