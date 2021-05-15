import React, { ReactNode, useState } from "react";
import { Menu, Typography } from "antd";
import SubMenu from "antd/lib/menu/SubMenu";
import { TextProps } from "antd/lib/typography/Text";
import { difference } from "lodash";
import Link from "next/link";

import { Warn } from ".";

const { Text } = Typography;

export interface MenuItem {
  key: string;
  target: string | null | MenuItem[];
  title: string;
  showWarn?: boolean;
  titleProps?: TextProps;
  cy?: string;
  icon?: ReactNode;
}

const getMenuItem = (
  item: MenuItem,
  initialKey: string
): [JSX.Element, string[]] => {
  if (typeof item.target === "string") {
    const inner = (
      <a>
        <Warn okay={!item.showWarn}>
          <Text {...item.titleProps}>{item.title}</Text>
        </Warn>
      </a>
    );
    const initialKeyPath = item.key === initialKey ? [initialKey] : [];
    return [
      <Menu.Item key={item.key} data-cy={item.cy} icon={item.icon}>
        <Link href={item.target}>{inner}</Link>
      </Menu.Item>,
      initialKeyPath,
    ];
  }
  const children = item?.target?.map((i) => getMenuItem(i, initialKey));
  const keyPath = children?.find((i) => i[1].length > 0);
  return [
    <SubMenu
      key={item.key}
      data-cy={item.cy}
      icon={item.icon}
      title={item.title}
    >
      {children?.map((a) => a[0])}
    </SubMenu>,
    keyPath ? keyPath[1].concat(item.key) : [],
  ];
};

const getKeyPeers = (key: string, items: MenuItem[]): string[] => {
  if (items.some((item) => item.key === key)) {
    return items.map((item) => item.key).filter((itemKey) => itemKey !== key);
  }
  const itemsWithChildren = items.filter(
    (item) =>
      typeof item.target !== "string" && typeof item.target !== "function"
  );
  for (let i = 0; i < itemsWithChildren.length; i++) {
    const res = getKeyPeers(key, itemsWithChildren[i].target as MenuItem[]);
    if (res.length > 0) {
      return res;
    }
  }
  return [];
};

type MenuProps = {
  items: MenuItem[];
  initialKey: string;
};

export const AdminSideMenu = ({ items, initialKey }: MenuProps) => {
  const [openKeys, setOpenKeys] = useState<string[]>([]);

  const menuItems = items.map((item) => getMenuItem(item, initialKey));
  const inner = menuItems.map((item) => item[0]);
  const initialOpenKeys = menuItems.find((i) => i[1].length > 0);

  if (openKeys.length === 0) {
    if (initialOpenKeys && initialOpenKeys[1].length > 0) {
      setOpenKeys(initialOpenKeys[1]);
    }
  }

  const onOpenChange = (prekeys: React.ReactText[]) => {
    const keys = prekeys.map((i) => i + "");
    if (keys.length < openKeys.length) {
      setOpenKeys(keys);
    } else {
      const newKeys = difference(keys, openKeys);
      if (newKeys.length !== 1) {
        throw new Error("Invalid AdminSideMenu item key");
      }
      const newKey = newKeys[0];
      const keyPeers = getKeyPeers(newKey, items);
      setOpenKeys(difference(keys, keyPeers));
    }
  };

  return (
    <Menu
      mode="inline"
      openKeys={openKeys}
      selectedKeys={[initialKey]}
      onOpenChange={onOpenChange}
    >
      {inner}
    </Menu>
  );
};
